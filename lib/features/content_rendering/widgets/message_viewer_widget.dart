import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail_flutter/enough_mail_flutter.dart';
import 'package:flutter/material.dart';

/// 邮件内容渲染组件
///
/// 使用官方 MimeMessageViewer 组件渲染邮件内容。
/// 支持 HTML、纯文本、multipart 等所有邮件格式。
/// 使用 flutter_inappwebview 引擎，性能优于 webview_flutter。
class MessageViewerWidget extends StatefulWidget {
  /// 原始 MIME 消息内容
  final String mimeMessageRaw;

  /// 是否阻止外部图片加载
  final bool blockExternalImages;

  /// 背景色
  final Color? backgroundColor;

  /// 是否可见
  ///
  /// 用于在页面返回动画前隐藏 WebView，避免残影
  final bool isVisible;

  /// 内容加载完成回调
  final VoidCallback? onContentReady;

  const MessageViewerWidget({
    super.key,
    required this.mimeMessageRaw,
    this.blockExternalImages = false,
    this.backgroundColor,
    this.isVisible = true,
    this.onContentReady,
  });

  @override
  State<MessageViewerWidget> createState() => _MessageViewerWidgetState();
}

class _MessageViewerWidgetState extends State<MessageViewerWidget> {
  /// 最大重试次数
  static const int _maxRetries = 30;

  /// 初始延迟时间
  static const Duration _initialDelay = Duration(milliseconds: 100);

  /// WebView 控制器
  InAppWebViewController? _controller;

  /// 是否已经通知内容加载完成
  bool _hasNotifiedReady = false;

  /// 当前重试次数
  int _retryCount = 0;

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  /// 处理 WebView 创建
  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
    // 使用定时器检查加载状态
    _checkLoadingStatus();
  }

  /// 检查加载状态
  ///
  /// 由于 MimeMessageViewer 没有暴露 onLoadStop 回调，
  /// 我们需要通过定时器检查 WebView 的加载状态
  void _checkLoadingStatus() {
    if (_retryCount >= _maxRetries) {
      debugPrint('MessageViewerWidget: 加载检查达到最大重试次数，标记为就绪');
      if (mounted) {
        widget.onContentReady?.call();
      }
      return;
    }

    _retryCount++;
    // 线性退避：每 10 次重试增加一档延迟
    final delay = _initialDelay * (_retryCount ~/ 10 + 1);

    Future.delayed(delay, () async {
      if (!mounted || _hasNotifiedReady) return;

      final controller = _controller;
      if (controller == null) {
        _checkLoadingStatus();
        return;
      }

      try {
        final isLoading = await controller.isLoading();
        if (!isLoading) {
          setState(() {
            _hasNotifiedReady = true;
          });
          widget.onContentReady?.call();
        } else {
          _checkLoadingStatus();
        }
      } catch (e) {
        _checkLoadingStatus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 解析 MIME 消息
    final mimeMessage = MimeMessage.parseFromText(widget.mimeMessageRaw);

    // 使用 Visibility 包裹，在返回动画前隐藏 WebView
    return Visibility(
      visible: widget.isVisible,
      maintainState: true, // 保持状态，避免重建
      child: Container(
        color: widget.backgroundColor,
        child: MimeMessageViewer(
          mimeMessage: mimeMessage,
          blockExternalImages: widget.blockExternalImages,
          onWebViewCreated: _onWebViewCreated,
        ),
      ),
    );
  }
}
