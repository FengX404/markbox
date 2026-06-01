import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';

import '../exceptions/mime_parse_exception.dart';
import '../models/email_content_type.dart';
import '../models/parsed_content.dart';
import '../models/parse_result.dart';

/// MIME 解析器工具类
///
/// 提供邮件 MIME 结构的遍历和内容提取功能
/// 支持 multipart 混合内容、文本内容、HTML 内容等多种 MIME 类型
class MimeParser {
  /// 支持的文本 MIME 类型
  static const Set<String> _supportedTextMimeTypes = {
    'text/plain',
    'text/html',
    'text/markdown',
  };

  /// 最大递归深度限制
  /// 防止畸形或循环 MIME 结构导致栈溢出
  static const int _maxDepth = 20;

  /// 支持的 multipart MIME 类型
  /// 预留常量，用于未来可能的 MIME 类型验证
  // ignore: unused_field
  static const Set<String> _supportedMultipartTypes = {
    'multipart/mixed',
    'multipart/alternative',
    'multipart/related',
  };

  /// 解析邮件消息
  ///
  /// [message] MIME 消息对象
  /// 返回解析结果，包含所有文本内容
  ParseResult parseMessage(MimeMessage message) {
    try {
      debugPrint('开始解析 MIME 消息');

      // 验证消息有效性
      if (message.mimeData == null) {
        debugPrint('MIME 数据为空');
        return ParseResult.failure(
          errorMessage: '邮件内容为空',
          errorType: ParseErrorType.emptyContent,
        );
      }

      // 提取所有文本内容
      final textContents = <ParsedContent>[];
      _traverseMimePart(message, textContents, 0);

      if (textContents.isEmpty) {
        debugPrint('未找到有效的文本内容');
        return ParseResult.failure(
          errorMessage: '未找到有效的文本内容',
          errorType: ParseErrorType.emptyContent,
        );
      }

      // 优先返回 Markdown > HTML > 纯文本
      final prioritizedContent = _prioritizeContent(textContents);

      debugPrint('MIME 消息解析成功，内容类型: ${prioritizedContent.type}');
      return ParseResult.success(prioritizedContent);
    } on MimeParseException catch (e) {
      debugPrint('MIME 解析异常: ${e.debugInfo}');
      return ParseResult.failure(
        errorMessage: e.message,
        errorType: ParseErrorType.formatError,
      );
    } catch (e, stackTrace) {
      debugPrint('MIME 解析未知异常: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      return ParseResult.failure(
        errorMessage: '解析邮件内容时发生错误: $e',
        errorType: ParseErrorType.unknown,
      );
    }
  }

  /// 递归遍历 MIME 部分
  ///
  /// [part] MIME 部分对象
  /// [contents] 收集的文本内容列表
  /// [depth] 当前递归深度，用于日志记录
  void _traverseMimePart(
    dynamic part,
    List<ParsedContent> contents,
    int depth,
  ) {
    if (depth > _maxDepth) {
      debugPrint('MIME 遍历深度超过最大值 $_maxDepth，停止递归');
      return;
    }
    final indent = '  ' * depth;
    debugPrint('$indent遍历 MIME 部分，深度: $depth');

    // 获取 Content-Type
    final contentType = _extractContentType(part);
    debugPrint('$indent Content-Type: $contentType');

    // 检查是否为 multipart 类型
    if (_isMultipart(contentType)) {
      debugPrint('$indent 检测到 multipart 类型，开始遍历子部分');
      _traverseMultipartPart(part, contents, depth);
    } else if (_isTextContentType(contentType)) {
      debugPrint('$indent 检测到文本类型，提取内容');
      _extractTextContent(part, contents, contentType);
    } else {
      debugPrint('$indent 跳过非文本类型: $contentType');
    }
  }

  /// 遍历 multipart 类型的 MIME 部分
  ///
  /// [part] MIME 部分
  /// [contents] 收集的文本内容列表
  /// [depth] 当前递归深度
  void _traverseMultipartPart(
    dynamic part,
    List<ParsedContent> contents,
    int depth,
  ) {
    try {
      // 获取子部分列表
      final parts = _getParts(part);
      if (parts == null || parts.isEmpty) {
        debugPrint('multipart 部分没有子内容');
        return;
      }

      debugPrint('multipart 包含 ${parts.length} 个子部分');

      // 递归遍历每个子部分
      for (var i = 0; i < parts.length; i++) {
        debugPrint('处理子部分 ${i + 1}/${parts.length}');
        _traverseMimePart(parts[i], contents, depth + 1);
      }
    } catch (e, stackTrace) {
      throw MimeParseException.invalidStructure(
        mimeType: _extractContentType(part),
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// 提取文本内容
  ///
  /// [part] MIME 部分
  /// [contents] 收集的文本内容列表
  /// [contentType] 内容类型
  void _extractTextContent(
    dynamic part,
    List<ParsedContent> contents,
    String contentType,
  ) {
    try {
      // 解码文本内容
      String? content;
      String? charset;
      String? encoding;

      // 根据 enough_mail 的 API 提取内容
      if (part is MimePart) {
        content = part.decodeContentText();
        // 从 Content-Type 头部获取 charset
        final contentTypeHeader = part.getHeaderContentType();
        charset = contentTypeHeader?.charset;
        // 从头部获取 Content-Transfer-Encoding
        encoding = _getHeaderValue(
          part.headers,
          'content-transfer-encoding',
        )?.toLowerCase();
      } else if (part is MimeMessage) {
        // 对于 MimeMessage，根据内容类型选择解码方法
        if (contentType.contains('text/html')) {
          content = part.decodeTextHtmlPart();
        } else if (contentType.contains('text/markdown')) {
          // Markdown 作为纯文本处理
          content = part.decodeTextPlainPart();
        } else {
          content = part.decodeTextPlainPart();
        }
        // 从 Content-Type 头部获取 charset
        final contentTypeHeader = part.getHeaderContentType();
        charset = contentTypeHeader?.charset;
        // 从头部获取 Content-Transfer-Encoding
        encoding = _getHeaderValue(
          part.headers,
          'content-transfer-encoding',
        )?.toLowerCase();
      }

      if (content == null || content.isEmpty) {
        debugPrint('文本内容为空，跳过');
        return;
      }

      // 确定内容类型枚举（严格按照 RFC 标准识别）
      final emailContentType = _mapToEmailContentType(contentType);

      // 创建解析内容对象
      final parsedContent = ParsedContent(
        type: emailContentType,
        content: content,
        charset: charset,
        encoding: encoding,
      );

      contents.add(parsedContent);
      debugPrint('成功提取文本内容，类型: $emailContentType, 长度: ${content.length}');
    } catch (e, stackTrace) {
      debugPrint('提取文本内容失败: $e');
      throw MimeParseException(
        message: '解码文本内容失败: $e',
        mimeType: contentType,
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// 从头部列表中获取指定名称的头部值
  ///
  /// [headers] 头部列表
  /// [name] 头部名称（不区分大小写）
  /// 返回头部值，如果不存在则返回 null
  String? _getHeaderValue(List<Header>? headers, String name) {
    if (headers == null) return null;
    final lowerName = name.toLowerCase();
    for (final header in headers) {
      if (header.lowerCaseName == lowerName) {
        return header.value;
      }
    }
    return null;
  }

  /// 提取 Content-Type 头部字段
  ///
  /// [part] MIME 部分
  /// 返回 Content-Type 字符串，如果不存在则返回空字符串
  String _extractContentType(dynamic part) {
    try {
      String? contentType;

      if (part is MimePart) {
        contentType = part.getHeaderContentType()?.mediaType.text.toLowerCase();
      } else if (part is MimeMessage) {
        contentType = part.getHeaderContentType()?.mediaType.text.toLowerCase();
      }

      return contentType ?? '';
    } catch (e) {
      debugPrint('提取 Content-Type 失败: $e');
      return '';
    }
  }

  /// 检查是否为 multipart 类型
  ///
  /// [contentType] 内容类型字符串
  /// 返回是否为 multipart 类型
  bool _isMultipart(String contentType) {
    return contentType.startsWith('multipart/');
  }

  /// 检查是否为支持的文本内容类型
  ///
  /// [contentType] 内容类型字符串
  /// 返回是否为支持的文本类型
  bool _isTextContentType(String contentType) {
    return _supportedTextMimeTypes.any((type) => contentType.contains(type));
  }

  /// 获取 MIME 部分的子部分列表
  ///
  /// [part] MIME 部分
  /// 返回子部分列表，如果没有则返回 null
  List<dynamic>? _getParts(dynamic part) {
    try {
      if (part is MimePart) {
        return part.parts;
      } else if (part is MimeMessage) {
        return part.parts;
      }
      return null;
    } catch (e) {
      debugPrint('获取子部分失败: $e');
      return null;
    }
  }

  /// 将 MIME 内容类型映射到 EmailContentType 枚举
  ///
  /// 严格按照 RFC 标准的 Content-Type 识别，不进行启发式检测
  /// [mimeType] MIME 类型字符串
  /// 返回对应的 EmailContentType 枚举值
  EmailContentType _mapToEmailContentType(String mimeType) {
    if (mimeType.contains('text/markdown')) {
      return EmailContentType.markdown;
    } else if (mimeType.contains('text/html')) {
      return EmailContentType.html;
    } else if (mimeType.contains('text/plain')) {
      return EmailContentType.plainText;
    }
    return EmailContentType.unknown;
  }

  /// 按优先级选择内容
  ///
  /// 优先级: Markdown > HTML > 纯文本
  /// [contents] 内容列表
  /// 返回优先级最高的内容
  ParsedContent _prioritizeContent(List<ParsedContent> contents) {
    // 优先查找 Markdown 内容
    final markdown = contents.where((c) => c.type == EmailContentType.markdown);
    if (markdown.isNotEmpty) {
      return markdown.first;
    }

    // 其次查找 HTML 内容
    final html = contents.where((c) => c.type == EmailContentType.html);
    if (html.isNotEmpty) {
      return html.first;
    }

    // 最后返回纯文本
    final plainText = contents.where(
      (c) => c.type == EmailContentType.plainText,
    );
    if (plainText.isNotEmpty) {
      return plainText.first;
    }

    // 如果都没有，返回第一个内容
    return contents.first;
  }

  /// 提取所有文本内容（不按优先级选择）
  ///
  /// [message] MIME 消息对象
  /// 返回所有文本内容的列表
  List<ParsedContent> extractAllTextContents(MimeMessage message) {
    try {
      debugPrint('开始提取所有文本内容');

      if (message.mimeData == null) {
        debugPrint('MIME 数据为空');
        return [];
      }

      final textContents = <ParsedContent>[];
      _traverseMimePart(message, textContents, 0);

      debugPrint('提取完成，共找到 ${textContents.length} 个文本内容');
      return textContents;
    } catch (e, stackTrace) {
      debugPrint('提取文本内容失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      return [];
    }
  }

  /// 检查 MIME 消息是否包含指定类型的内容
  ///
  /// [message] MIME 消息对象
  /// [contentType] 要检查的内容类型
  /// 返回是否包含该类型的内容
  bool hasContentType(MimeMessage message, EmailContentType contentType) {
    try {
      final contents = extractAllTextContents(message);
      return contents.any((c) => c.type == contentType);
    } catch (e) {
      debugPrint('检查内容类型失败: $e');
      return false;
    }
  }

  /// 获取 MIME 消息的结构信息
  ///
  /// [message] MIME 消息对象
  /// 返回结构信息的字符串描述
  String getStructureInfo(MimeMessage message) {
    try {
      final buffer = StringBuffer();
      buffer.writeln('MIME 结构信息:');
      _buildStructureInfo(message, buffer, 0);
      return buffer.toString();
    } catch (e) {
      return '获取结构信息失败: $e';
    }
  }

  /// 递归构建结构信息
  ///
  /// [part] MIME 部分
  /// [buffer] 字符串缓冲区
  /// [depth] 当前深度
  void _buildStructureInfo(dynamic part, StringBuffer buffer, int depth) {
    if (depth > _maxDepth) {
      buffer.writeln('${'  ' * depth}... (深度超过最大值 $_maxDepth)');
      return;
    }
    final indent = '  ' * depth;
    final contentType = _extractContentType(part);

    buffer.writeln('$indent- Content-Type: $contentType');

    // 如果是 multipart，递归显示子部分
    if (_isMultipart(contentType)) {
      final parts = _getParts(part);
      if (parts != null && parts.isNotEmpty) {
        for (var i = 0; i < parts.length; i++) {
          buffer.writeln('$indent  子部分 ${i + 1}:');
          _buildStructureInfo(parts[i], buffer, depth + 2);
        }
      }
    }
  }
}
