#!/usr/bin/env python3
"""并行分段下载器：为不可靠代理/网络设计。

用法: parallel_dl.py <url> <输出文件> [期望sha256] [并行数]

原理：先探测总大小，切分成小块，多个 worker 各自用 Range 续传重试，
最后拼接并校验 sha256。适合 gh-proxy 这类单连接易断的镜像。
"""
import hashlib
import os
import subprocess
import sys
import threading

CHUNK = 512 * 1024  # 每段 512KB，与单连接实际可传输量级匹配


def curl_range(urls: list, start: int, end: int, path: str, retries: int = 60):
    """下载 [start, end] 到 path，多个 URL 轮换重试。"""
    for i in range(retries):
        have = os.path.getsize(path) if os.path.exists(path) else 0
        want = end - start + 1
        if have >= want:
            return True
        url = urls[i % len(urls)]  # 轮换直连与镜像
        r = subprocess.run(
            ["curl", "-sL", "--connect-timeout", "8", "-m", "120",
             "-r", f"{start + have}-{end}", "-o", path + ".part", url],
            capture_output=True)
        if r.returncode == 0 and os.path.exists(path + ".part"):
            with open(path, "ab") as out, open(path + ".part", "rb") as part:
                out.write(part.read())
            os.unlink(path + ".part")
    return os.path.getsize(path) >= want


def probe_size(urls: list) -> int:
    for url in urls:
        try:
            r = subprocess.run(
                ["curl", "-sIL", "--connect-timeout", "8", "-m", "60", url],
                capture_output=True, text=True, timeout=70)
            size = None
            for line in r.stdout.splitlines():
                low = line.lower()
                if low.startswith("content-range:"):
                    size = int(low.rsplit("/", 1)[1].strip())
                elif low.startswith("content-length:") and size is None:
                    v = int(low.split(":", 1)[1].strip())
                    if v > 0:
                        size = v
            if size is not None:
                return size
        except Exception:
            continue
    raise RuntimeError(f"无法探测文件大小（所有 URL 均失败）: {urls}")


def main():
    # 第 1 个参数可以是逗号分隔的多个同内容 URL（直连 + 镜像轮换）
    urls = sys.argv[1].split(",")
    out = sys.argv[2]
    want_hash = sys.argv[3] if len(sys.argv) > 3 else None
    workers = int(sys.argv[4]) if len(sys.argv) > 4 else 16

    total = probe_size(urls)
    print(f"总大小: {total} bytes, 并行 {workers}")
    tmpdir = out + ".segments"
    os.makedirs(tmpdir, exist_ok=True)

    segments = []
    for i, start in enumerate(range(0, total, CHUNK)):
        segments.append((i, start, min(start + CHUNK, total) - 1))

    failures = []
    lock = threading.Lock()
    done_count = [0]

    def worker(idx):
        while segments:
            with lock:
                if not segments:
                    return
                i, s, e = segments.pop()
            path = os.path.join(tmpdir, f"{i:05d}")
            ok = curl_range(urls, s, e, path)
            with lock:
                done_count[0] += 1
                if not ok:
                    failures.append(i)
                print(f"\r{done_count[0]} 段完成", end="", flush=True)
        return

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    print()
    if failures:
        raise RuntimeError(f"以下分段最终失败: {failures}")

    with open(out, "wb") as fout:
        for i in range(len(range(0, total, CHUNK))):
            with open(os.path.join(tmpdir, f"{i:05d}"), "rb") as fin:
                fout.write(fin.read())
    import shutil
    shutil.rmtree(tmpdir)

    got = hashlib.sha256(open(out, "rb").read()).hexdigest()
    print(f"sha256: {got}")
    if want_hash and got != want_hash:
        raise RuntimeError(f"sha256 不匹配! 期望 {want_hash}")
    print(f"完成: {out} ({os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
