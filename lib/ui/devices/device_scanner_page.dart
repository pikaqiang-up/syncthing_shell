import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 设备 ID 扫码页：识别二维码后回传内容并退出。
///
/// 只识别 QR；无相机权限/相机不可用时提示并允许返回。
class DeviceIdScannerPage extends StatefulWidget {
  const DeviceIdScannerPage({super.key});

  @override
  State<DeviceIdScannerPage> createState() => _DeviceIdScannerPageState();
}

class _DeviceIdScannerPageState extends State<DeviceIdScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描设备二维码'),
        actions: [
          // 手电筒（设备支持时）
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.no_photography_outlined,
                        size: 56, color: scheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      switch (error.errorCode) {
                        MobileScannerErrorCode.permissionDenied =>
                          '相机权限被拒绝，请在系统设置中允许',
                        _ => '相机不可用：${error.errorCode.name}',
                      },
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('返回'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // 取景框装饰
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: scheme.primary, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Center(
            child: Text(
              '对准另一台设备显示的二维码',
              style: TextStyle(color: scheme.onInverseSurface),
            ),
          ),
        ),
      ]),
    );
  }
}
