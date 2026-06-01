import 'package:flutter/material.dart';
import 'package:markbox/features/content_rendering/widgets/renderers/markdown_renderer.dart';
import 'package:markbox/features/content_rendering/widgets/renderers/plain_text_renderer.dart';
import 'package:markbox/features/content_rendering/widgets/empty_state_widget.dart';
import 'package:markbox/features/email_parser/models/email_content_type.dart';

/// 内容渲染器主组件
///
/// 根据内容类型自动选择对应的渲染器（Markdown、HTML、纯文本）
/// 简化版本：直接渲染内容，不使用复杂的状态管理
class ContentRendererWidget extends StatelessWidget {
  /// 要渲染的内容
  final String content;

  /// 链接点击回调（可选）
  final void Function(String)? onTapLink;

  /// 背景色
  final Color? backgroundColor;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 已知的内容类型（可选）
  ///
  /// 如果传入，将跳过自动检测直接使用此类型
  final EmailContentType? contentType;

  /// 内容加载完成回调（可选）
  final VoidCallback? onContentReady;

  /// 创建内容渲染器
  const ContentRendererWidget({
    super.key,
    required this.content,
    this.onTapLink,
    this.backgroundColor,
    this.padding,
    this.contentType,
    this.onContentReady,
  });

  @override
  Widget build(BuildContext context) {
    // 如果内容为空，显示空状态
    if (content.isEmpty) {
      return Container(
        color: backgroundColor,
        child: const EmptyStateWidget(
          title: '内容为空',
          icon: Icons.description_outlined,
        ),
      );
    }

    // 获取内容类型
    final actualContentType = contentType ?? _detectContentType(content);

    // 根据内容类型选择渲染器
    switch (actualContentType) {
      case EmailContentType.markdown:
        return MarkdownRenderer(
          markdownData: content,
          onTapLink: onTapLink,
          onContentReady: onContentReady,
        );

      case EmailContentType.html:
        // HTML 类型应该使用 MessageViewerWidget，这里作为降级处理
        // 去除 HTML 标签后显示纯文本
        final strippedContent = content.replaceAll(
          RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false),
          '',
        );
        return PlainTextRenderer(
          content: strippedContent,
          backgroundColor: backgroundColor ?? const Color(0xFF1E1E1E),
          padding: padding is EdgeInsets
              ? padding as EdgeInsets
              : const EdgeInsets.all(16.0),
        );

      case EmailContentType.plainText:
        return PlainTextRenderer(
          content: content,
          backgroundColor: backgroundColor ?? const Color(0xFF1E1E1E),
          padding: padding is EdgeInsets
              ? padding as EdgeInsets
              : const EdgeInsets.all(16.0),
        );

      case EmailContentType.unknown:
        // 未知类型，尝试自动检测
        final detectedType = _detectContentType(content);
        if (detectedType == EmailContentType.markdown) {
          return MarkdownRenderer(markdownData: content, onTapLink: onTapLink);
        }
        return PlainTextRenderer(
          content: content,
          backgroundColor: backgroundColor ?? const Color(0xFF1E1E1E),
          padding: padding is EdgeInsets
              ? padding as EdgeInsets
              : const EdgeInsets.all(16.0),
        );
    }
  }

  /// 检测内容类型
  ///
  /// 根据内容特征判断是 Markdown、HTML 还是纯文本
  EmailContentType _detectContentType(String content) {
    // 去除首尾空白
    final trimmedContent = content.trim();

    if (trimmedContent.isEmpty) {
      return EmailContentType.unknown;
    }

    // 1. 检查是否为 HTML（优先级最高）
    if (_isHtml(trimmedContent)) {
      return EmailContentType.html;
    }

    // 2. 检查是否为 Markdown
    if (_isMarkdown(trimmedContent)) {
      return EmailContentType.markdown;
    }

    // 3. 默认为纯文本
    return EmailContentType.plainText;
  }

  /// 判断是否为 HTML 内容
  ///
  /// 检查内容是否包含 HTML 标签
  bool _isHtml(String content) {
    // 转换为小写进行匹配
    final lowerContent = content.toLowerCase();

    // 1. 检查是否包含 DOCTYPE 声明（强特征）
    if (lowerContent.contains('<!doctype html')) {
      return true;
    }

    // 2. 检查是否包含 html 或 body 标签（强特征）
    if (lowerContent.contains('<html') || lowerContent.contains('<body')) {
      return true;
    }

    // 3. 检查是否包含常见的 HTML 结构标签（中等特征）
    final structuralTags = [
      '<div',
      '<span',
      '<p>',
      '<p ',
      '<table',
      '<ul',
      '<ol',
      '<header',
      '<footer',
      '<section',
      '<article',
    ];
    for (final tag in structuralTags) {
      if (lowerContent.contains(tag)) {
        return true;
      }
    }

    // 4. 检查是否包含闭合标签（弱特征，但比较可靠）
    final closeTagPattern = RegExp(r'</[a-zA-Z][a-zA-Z0-9]*>');
    final closeTagMatches = closeTagPattern.allMatches(content);
    // 如果有 2 个或以上的闭合标签，很可能是 HTML
    if (closeTagMatches.length >= 2) {
      return true;
    }

    // 5. 检查是否包含常见的 HTML 属性（弱特征）
    if (lowerContent.contains('class=') || lowerContent.contains('style=')) {
      return true;
    }

    return false;
  }

  /// 判断是否为 Markdown 内容
  ///
  /// 检查内容是否包含 Markdown 特征标记
  bool _isMarkdown(String content) {
    // Markdown 特征标记
    int markdownScore = 0;

    // 1. 检查标题标记 (# ## ### 等)
    final headingPattern = RegExp(r'^#{1,6}\s+.+$', multiLine: true);
    final headingMatches = headingPattern.allMatches(content);
    markdownScore += headingMatches.length * 2;

    // 2. 检查列表标记 (- * + 或 1. 2. 等)
    final unorderedListPattern = RegExp(r'^[\s]*[-*+]\s+.+$', multiLine: true);
    final orderedListPattern = RegExp(r'^[\s]*\d+\.\s+.+$', multiLine: true);
    markdownScore += unorderedListPattern.allMatches(content).length;
    markdownScore += orderedListPattern.allMatches(content).length;

    // 3. 检查代码块 (``` 或 ~~~)
    final codeBlockPattern = RegExp(r'```[\s\S]*?```');
    final codeBlockMatches = codeBlockPattern.allMatches(content);
    markdownScore += codeBlockMatches.length * 3;

    // 4. 检查行内代码 (`code`)
    final inlineCodePattern = RegExp(r'`[^`]+`');
    markdownScore += inlineCodePattern.allMatches(content).length;

    // 5. 检查强调标记 (**bold** *italic* ~~strike~~)
    final boldPattern = RegExp(r'\*\*[^*]+\*\*');
    final italicPattern = RegExp(r'(?<!\*)\*(?!\*)([^*]+)(?<!\*)\*(?!\*)');
    final strikePattern = RegExp(r'~~[^~]+~~');
    markdownScore += boldPattern.allMatches(content).length;
    markdownScore += italicPattern.allMatches(content).length;
    markdownScore += strikePattern.allMatches(content).length;

    // 6. 检查链接标记 [text](url)
    final linkPattern = RegExp(r'\[.+?\]\(.+?\)');
    markdownScore += linkPattern.allMatches(content).length * 2;

    // 7. 检查图片标记 ![alt](url)
    final imagePattern = RegExp(r'!\[.+?\]\(.+?\)');
    markdownScore += imagePattern.allMatches(content).length * 2;

    // 8. 检查引用标记 (> text)
    final blockquotePattern = RegExp(r'^>\s+.+$', multiLine: true);
    markdownScore += blockquotePattern.allMatches(content).length;

    // 9. 检查水平分割线 (--- *** ___)
    final hrPattern = RegExp(r'^[-*_]{3,}$', multiLine: true);
    markdownScore += hrPattern.allMatches(content).length * 2;

    // 10. 检查表格标记 (| column |)
    final tablePattern = RegExp(r'\|.+\|');
    markdownScore += tablePattern.allMatches(content).length;

    // 如果 Markdown 特征分数达到阈值，则认为是 Markdown
    // 阈值设为 5，提高准确性，避免误判
    return markdownScore >= 5;
  }
}
