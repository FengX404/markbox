import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_code_view/flutter_code_view.dart';
import 'package:markdown/markdown.dart' as md;
import 'lazy_image.dart';

/// Markdown 渲染器组件
///
/// 用于渲染 Markdown 内容，支持深色主题样式
/// 包含异常捕获和降级逻辑，解析失败时显示原始内容
class MarkdownRenderer extends StatefulWidget {
  /// 要渲染的 Markdown 文本
  final String markdownData;

  /// 可选的链接点击回调
  final void Function(String)? onTapLink;

  /// 内容加载完成回调
  final VoidCallback? onContentReady;

  /// 创建 Markdown 渲染器
  const MarkdownRenderer({
    super.key,
    required this.markdownData,
    this.onTapLink,
    this.onContentReady,
  });

  @override
  State<MarkdownRenderer> createState() => _MarkdownRendererState();
}

class _MarkdownRendererState extends State<MarkdownRenderer> {
  /// 渲染错误信息
  String? _errorMessage;

  /// 是否降级显示原始内容
  bool _shouldFallback = false;

  @override
  void initState() {
    super.initState();
    _tryRenderMarkdown();
    // 在首帧渲染后通知内容加载完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onContentReady?.call();
    });
  }

  @override
  void didUpdateWidget(MarkdownRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当内容变化时，重新尝试渲染
    if (oldWidget.markdownData != widget.markdownData) {
      _tryRenderMarkdown();
    }
  }

  /// 尝试渲染 Markdown，捕获异常
  void _tryRenderMarkdown() {
    try {
      // 重置错误状态
      setState(() {
        _errorMessage = null;
        _shouldFallback = false;
      });

      // 尝试解析 Markdown 内容
      // 如果内容有严重问题，这里会抛出异常
      md.Document(
        extensionSet: md.ExtensionSet.gitHubWeb,
        encodeHtml: false,
      ).parseLines(widget.markdownData.split('\n'));

      // 如果解析成功，保持正常渲染状态
    } catch (e) {
      // 捕获异常，设置降级状态
      debugPrint('Markdown 渲染失败: $e');
      setState(() {
        _errorMessage = e.toString();
        _shouldFallback = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果需要降级，显示原始内容
    if (_shouldFallback) {
      return _buildFallbackWidget();
    }

    // 正常渲染 Markdown
    try {
      return MarkdownBody(
        data: widget.markdownData,
        styleSheet: _buildMarkdownStyleSheet(context),
        onTapLink: (String text, String? href, String title) {
          if (widget.onTapLink != null && href != null) {
            widget.onTapLink!(href);
          }
        },
        builders: {'pre': CodeBlockBuilder()},
        extensionSet: md.ExtensionSet.gitHubWeb,
        // 添加错误处理回调
        onTapText: () {},
        // 使用延迟加载图片构建器
        imageBuilder: (uri, title, alt) {
          return LazyImageBuilder.build(
            uri: uri.toString(),
            title: title,
            alt: alt,
          );
        },
      );
    } catch (e) {
      // 渲染过程中出现异常，降级显示
      debugPrint('Markdown 渲染过程异常: $e');
      return _buildFallbackWidget();
    }
  }

  /// 构建降级显示组件
  ///
  /// 当 Markdown 解析失败时，显示原始内容
  Widget _buildFallbackWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 错误提示
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Markdown 解析失败，显示原始内容',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 原始内容
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                widget.markdownData,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建 Markdown 样式表（深色主题）
  MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 深色主题颜色
    const darkBackgroundColor = Color(0xFF1E1E1E);
    const darkCodeBackgroundColor = Color(0xFF2D2D2D);
    const linkColor = Color(0xFFBB86FC);
    const textColor = Colors.white70;

    return MarkdownStyleSheet(
      // 基础文本样式
      p: TextStyle(
        fontSize: 16,
        height: 1.6,
        color: isDark ? textColor : Colors.black87,
      ),

      // 标题样式 - 使用不同大小和粗细
      h1: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
        height: 1.3,
      ),
      h2: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
        height: 1.3,
      ),
      h3: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black,
        height: 1.3,
      ),
      h4: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black,
        height: 1.3,
      ),
      h5: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white : Colors.black,
        height: 1.3,
      ),
      h6: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white70 : Colors.black87,
        height: 1.3,
      ),

      // 链接样式 - 使用紫色
      a: TextStyle(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      ),

      // 强调文本
      em: TextStyle(
        fontStyle: FontStyle.italic,
        color: isDark ? textColor : Colors.black87,
      ),
      strong: TextStyle(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),

      // 删除线
      del: TextStyle(
        decoration: TextDecoration.lineThrough,
        color: isDark ? Colors.white54 : Colors.black54,
      ),

      // 引用块
      blockquote: TextStyle(
        fontSize: 16,
        color: isDark ? Colors.white60 : Colors.black54,
        fontStyle: FontStyle.italic,
        height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? darkBackgroundColor : Colors.grey.shade100,
        border: Border(left: BorderSide(color: linkColor, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),

      // 代码样式
      code: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 14,
        color: isDark ? Colors.white : Colors.black87,
        backgroundColor: isDark
            ? darkCodeBackgroundColor
            : Colors.grey.shade200,
      ),
      codeblockPadding: const EdgeInsets.all(0),
      codeblockDecoration: BoxDecoration(
        color: isDark ? darkCodeBackgroundColor : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),

      // 行内代码
      codeblockAlign: WrapAlignment.start,

      // 列表样式
      listBullet: TextStyle(
        fontSize: 16,
        color: isDark ? textColor : Colors.black87,
      ),
      listIndent: 24,

      // 表格样式
      tableHead: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
      tableBody: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: isDark ? textColor : Colors.black87,
      ),
      tableBorder: TableBorder.all(
        color: isDark ? Colors.white24 : Colors.black26,
        width: 1,
      ),
      tableCellsPadding: const EdgeInsets.all(8),

      // 水平分割线
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white24 : Colors.black26,
            width: 1,
          ),
        ),
      ),

      // 图片样式
      img: TextStyle(fontSize: 16, color: isDark ? textColor : Colors.black87),
    );
  }
}

/// 代码块构建器
///
/// 使用 FlutterCodeView 渲染代码块，支持语法高亮、行号显示和自动语言检测
class CodeBlockBuilder extends MarkdownElementBuilder {
  /// 语言映射表 - 将语言标识符映射到对应的 Languages 枚举
  static final Map<String, Languages> _languageMap = {
    // 编程语言
    'dart': Languages.dart,
    'javascript': Languages.javascript,
    'js': Languages.javascript,
    'typescript': Languages.typescript,
    'ts': Languages.typescript,
    'python': Languages.python,
    'py': Languages.python,
    'java': Languages.java,
    'go': Languages.go,
    'golang': Languages.go,
    'rust': Languages.rust,
    'rs': Languages.rust,
    'kotlin': Languages.kotlin,
    'swift': Languages.swift,
    'c': Languages.c1,
    'cpp': Languages.cpp,
    'c++': Languages.cpp,
    'csharp': Languages.cs,
    'cs': Languages.cs,
    'c#': Languages.cs,
    'ruby': Languages.ruby,
    'php': Languages.php,
    'perl': Languages.perl,
    'scala': Languages.scala,
    'r': Languages.r,
    // 标记语言和数据格式
    'html': Languages.htmlbars,
    'xml': Languages.xml,
    'css': Languages.css,
    'json': Languages.json,
    'yaml': Languages.yaml,
    'yml': Languages.yaml,
    'markdown': Languages.markdown,
    'md': Languages.markdown,
    // 脚本语言
    'bash': Languages.bash,
    'sh': Languages.bash,
    'shell': Languages.bash,
    'zsh': Languages.bash,
    'sql': Languages.sql,
    'dockerfile': Languages.dockerfile,
    'docker': Languages.dockerfile,
    // 其他
    'diff': Languages.diff,
    'plaintext': Languages.plaintext,
    'text': Languages.plaintext,
  };

  /// 获取语言枚举
  ///
  /// 如果语言标识符未找到，返回 null 表示使用自动检测
  Languages? _getLanguage(String language) {
    final normalizedLanguage = language.toLowerCase().trim();
    return _languageMap[normalizedLanguage];
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // 获取代码内容
    final codeContent = element.textContent;

    // 获取语言标识
    final languageClass = element.attributes['class'] ?? '';
    final language = languageClass.replaceFirst('language-', '');

    // 获取语言枚举
    final languageEnum = language.isNotEmpty ? _getLanguage(language) : null;

    // 返回代码块组件
    return _CodeBlockWidget(
      codeContent: codeContent,
      language: languageEnum,
      autoDetection: language.isEmpty, // 没有指定语言时启用自动检测
    );
  }
}

/// 代码块组件
///
/// 使用 FlutterCodeView 渲染，支持语法高亮、行号显示和复制功能
class _CodeBlockWidget extends StatelessWidget {
  /// 代码内容
  final String codeContent;

  /// 语言枚举
  final Languages? language;

  /// 是否启用自动检测
  final bool autoDetection;

  const _CodeBlockWidget({
    required this.codeContent,
    this.language,
    this.autoDetection = false,
  });

  /// 复制代码到剪贴板
  Future<void> _copyCode(BuildContext context) async {
    try {
      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: codeContent));

      // 显示成功提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // 显示错误提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('复制失败: $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Stack(
        children: [
          // 代码内容
          FlutterCodeView(
            source: codeContent,
            language: language,
            autoDetection: autoDetection,
            themeType: ThemeType.atomOneDark,
            showLineNumbers: true,
            fontSize: 14,
            selectionColor: Colors.blue.withValues(alpha: 0.3),
            padding: const EdgeInsets.fromLTRB(16, 16, 50, 16),
          ),
          // 复制按钮 - 位于右上角
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _copyCode(context),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.copy,
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
