import 'dart:async';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';

import '../shared/models/email.dart';
import '../shared/models/imap_config.dart';
import '../features/email_parser/models/email_content_type.dart';
import '../features/email_parser/services/mime_parser.dart';

/// 邮件服务错误类型
enum EmailServiceErrorType {
  /// 网络连接错误
  networkError,

  /// IMAP 连接断开
  connectionLost,

  /// 数据解析失败
  parseError,

  /// 认证失败
  authenticationFailed,

  /// 超时错误
  timeoutError,

  /// 未知错误
  unknown,
}

/// 邮件服务异常
class EmailServiceException implements Exception {
  /// 错误消息
  final String message;

  /// 错误类型
  final EmailServiceErrorType errorType;

  /// 原始异常
  final dynamic originalError;

  EmailServiceException(
    this.message, {
    this.errorType = EmailServiceErrorType.unknown,
    this.originalError,
  });

  @override
  String toString() => 'EmailServiceException: $message';
}

/// 邮件获取结果
class FetchEmailsResult {
  /// 邮件列表
  final List<Email> emails;

  /// 是否有更多数据
  final bool hasMore;

  /// 总数量（如果服务器支持）
  final int? totalCount;

  FetchEmailsResult({
    required this.emails,
    required this.hasMore,
    this.totalCount,
  });
}

/// 邮件服务
///
/// 封装 IMAP 邮件获取逻辑，提供分页获取邮件的功能
class EmailService {
  /// IMAP 客户端实例
  ImapClient? _client;

  /// 当前连接的配置
  ImapConfig? _currentConfig;

  /// 连接超时时间（毫秒）
  static const int connectionTimeoutMs = 10000;

  /// 操作超时时间（毫秒）
  static const int operationTimeoutMs = 30000;

  /// 默认每页邮件数量
  static const int defaultPageSize = 50;

  /// 连接到 IMAP 服务器
  ///
  /// [config] IMAP 配置信息
  /// 如果已经连接到相同的配置，则复用现有连接
  Future<void> connect(ImapConfig config) async {
    // 如果已经连接到相同的配置，直接返回
    if (_client != null &&
        _currentConfig != null &&
        _currentConfig!.server == config.server &&
        _currentConfig!.email == config.email) {
      // 检查连接是否仍然有效
      if (_client!.isConnected) {
        return;
      }
    }

    // 断开现有连接
    await disconnect();

    // 创建新的客户端
    _client = ImapClient(isLogEnabled: kDebugMode);

    try {
      debugPrint('开始连接 IMAP 服务器: ${config.server}:${config.port}');

      // 连接到服务器
      await _client!
          .connectToServer(config.server, config.port, isSecure: config.useSSL)
          .timeout(
            const Duration(milliseconds: connectionTimeoutMs),
            onTimeout: () {
              throw TimeoutException('连接超时');
            },
          );

      debugPrint('IMAP 服务器连接成功');

      // 登录认证
      await _client!.login(config.email, config.password);

      debugPrint('IMAP 认证成功');

      // 保存当前配置
      _currentConfig = config;
    } catch (e) {
      // 连接失败，清理资源
      await disconnect();
      rethrow;
    }
  }

  /// 断开 IMAP 连接
  Future<void> disconnect() async {
    if (_client != null) {
      try {
        if (_client!.isConnected) {
          await _client!.logout();
        }
      } catch (e) {
        debugPrint('断开连接时出错: $e');
      } finally {
        try {
          _client = null;
          _currentConfig = null;
        } catch (e) {
          debugPrint('清理客户端资源时出错: $e');
        }
      }
    }
  }

  /// 释放资源
  ///
  /// 安全地断开连接并释放所有资源
  Future<void> dispose() async {
    try {
      await disconnect();
    } catch (e) {
      debugPrint('释放 EmailService 资源时出错: $e');
    }
  }

  /// 检查连接状态
  bool get isConnected => _client?.isConnected ?? false;

  /// 获取邮件列表
  ///
  /// [config] IMAP 配置信息
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量，默认 50
  /// [mailbox] 邮箱文件夹名称，默认为 INBOX
  /// 返回邮件列表和分页信息
  Future<FetchEmailsResult> fetchEmails({
    required ImapConfig config,
    int page = 1,
    int pageSize = defaultPageSize,
    String mailbox = 'INBOX',
  }) async {
    // 参数验证
    if (page < 1) {
      throw EmailServiceException(
        '页码必须大于等于 1',
        errorType: EmailServiceErrorType.parseError,
      );
    }

    if (pageSize < 1 || pageSize > 1000) {
      throw EmailServiceException(
        '每页数量必须在 1-1000 之间',
        errorType: EmailServiceErrorType.parseError,
      );
    }

    try {
      // 确保已连接
      await connect(config);

      // 选择邮箱文件夹
      final mailboxResult = await _client!
          .selectMailboxByPath(mailbox)
          .timeout(
            const Duration(milliseconds: operationTimeoutMs),
            onTimeout: () {
              throw TimeoutException('选择邮箱超时');
            },
          );

      // 获取邮件总数
      final totalCount = mailboxResult.messagesExists;

      // 计算本页对应的 IMAP 序列号范围
      // IMAP 序列号：1 = 最旧，totalCount = 最新
      final highSeq = totalCount - (page - 1) * pageSize;
      final lowSeq = (highSeq - pageSize + 1).clamp(1, totalCount);

      // 检查是否还有更多数据
      final hasMore = lowSeq > 1;

      // 如果窗口起始 <= 0，说明没有数据了
      if (highSeq <= 0) {
        return FetchEmailsResult(
          emails: [],
          hasMore: false,
          totalCount: totalCount,
        );
      }

      debugPrint('获取邮件: 序号 $lowSeq 到 $highSeq (第$page页)');

      // 使用 IMAP 序列号范围精确获取指定页的邮件
      // criteria 包含 UID、ENVELOPE 和 INTERNALDATE 以确保获取邮件日期信息和唯一标识符
      final fetchResult = await _client!
          .fetchMessages(
            MessageSequence.fromRange(lowSeq, highSeq),
            '(UID FLAGS ENVELOPE INTERNALDATE BODY.PEEK[])',
          )
          .timeout(
            const Duration(milliseconds: operationTimeoutMs),
            onTimeout: () {
              throw TimeoutException('获取邮件超时');
            },
          );

      // 转换为 Email 模型列表
      // fetchMessages 返回的邮件按序列号从小到大排序（最旧→最新），反转得到最新优先
      final messages = fetchResult.messages.reversed.toList();
      final emails = <Email>[];
      for (final message in messages) {
        try {
          final email = _convertToEmail(message);
          emails.add(email);
        } catch (e) {
          debugPrint('解析邮件失败: ${message.sequenceId}, 错误: $e');
          // 跳过解析失败的邮件，继续处理下一封
        }
      }

      debugPrint('成功获取 ${emails.length} 封邮件');

      return FetchEmailsResult(
        emails: emails,
        hasMore: hasMore,
        totalCount: totalCount,
      );
    } on EmailServiceException {
      rethrow;
    } on SocketException catch (e) {
      throw EmailServiceException(
        '网络连接失败: ${e.message}',
        errorType: EmailServiceErrorType.networkError,
        originalError: e,
      );
    } on TimeoutException catch (e) {
      throw EmailServiceException(
        '操作超时: ${e.message}',
        errorType: EmailServiceErrorType.timeoutError,
        originalError: e,
      );
    } on ImapException catch (e) {
      // 检查是否是连接断开
      if (!_client!.isConnected) {
        throw EmailServiceException(
          'IMAP 连接已断开',
          errorType: EmailServiceErrorType.connectionLost,
          originalError: e,
        );
      }

      // 检查是否是认证失败
      final errorMessage = e.message?.toLowerCase() ?? '';
      if (errorMessage.contains('authentication') ||
          errorMessage.contains('login') ||
          errorMessage.contains('credentials')) {
        throw EmailServiceException(
          '认证失败: ${e.message}',
          errorType: EmailServiceErrorType.authenticationFailed,
          originalError: e,
        );
      }

      throw EmailServiceException(
        'IMAP 协议错误: ${e.message}',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    } catch (e) {
      throw EmailServiceException(
        '获取邮件失败: $e',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    }
  }

  /// 从邮件内容中提取纯文本预览
  ///
  /// [content] 原始邮件内容（可能是纯文本或 HTML）
  /// 返回清理后的纯文本预览，最多 100 个字符
  String? _extractPreviewText(String? content) {
    if (content == null || content.isEmpty) {
      return null;
    }

    String text = content;

    // 去除 HTML 标签
    text = text.replaceAll(
      RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false),
      '',
    );

    // 去除 DOCTYPE、XML 声明等
    text = text.replaceAll(
      RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'<\?xml[^>]*\?>', caseSensitive: false), '');

    // 去除 HTML 实体
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&#39;', "'");
    text = text.replaceAll(RegExp(r'&#\d+;'), '');

    // 去除多余的空白字符
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    text = text.trim();

    // 截取前 100 个字符（使用 characters 避免拆分 emoji 等代理对）
    if (text.characters.length > 100) {
      text = '${text.characters.take(100).toString()}...';
    }

    return text.isEmpty ? null : text;
  }

  /// 月份名称到数字的映射
  static const Map<String, int> _monthMap = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// 解析 RFC 2822 日期格式
  ///
  /// [dateStr] RFC 2822 格式的日期字符串，如 "Sun, 19 Apr 2026 15:28:05 +0800"
  /// 返回解析后的 DateTime，解析失败返回 null
  DateTime? _parseRfc2822Date(String dateStr) {
    try {
      // 格式: Day, DD Mon YYYY HH:MM:SS +ZZZZ
      // 示例: Sun, 19 Apr 2026 15:28:05 +0800
      final parts = dateStr.trim().split(RegExp(r'\s+'));
      if (parts.length < 5) return null;

      // 跳过星期几（parts[0]），从日期开始解析
      int day;
      int month;
      int year;
      String timeStr;
      String tzStr;

      // 检查第一个部分是否是星期几（带逗号）
      int startIndex = 0;
      if (parts[0].endsWith(',')) {
        startIndex = 1;
      }

      day = int.parse(parts[startIndex].replaceAll(',', ''));
      month = _monthMap[parts[startIndex + 1]] ?? 1;
      year = int.parse(parts[startIndex + 2]);
      timeStr = parts[startIndex + 3];
      tzStr = parts[startIndex + 4];

      // 解析时间
      final timeParts = timeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);

      // 解析时区
      // +0800 表示东八区（比 UTC 快 8 小时），-0500 表示西五区（比 UTC 慢 5 小时）
      final tzSign = tzStr[0] == '-' ? -1 : 1;
      final tzHours = int.parse(tzStr.substring(1, 3));
      final tzMinutes = int.parse(tzStr.substring(3, 5));
      final tzOffsetMinutes = tzSign * (tzHours * 60 + tzMinutes);

      // 解析的时间是本地时间（带时区），需要转换为 UTC
      // 例如：15:28:05 +0800 表示东八区 15:28，对应 UTC 07:28
      // 所以需要减去时区偏移量得到 UTC 时间
      final localTime = DateTime.utc(year, month, day, hour, minute, second);
      final utcTime = localTime.subtract(Duration(minutes: tzOffsetMinutes));

      // 返回 UTC 时间，Flutter 会自动根据设备时区显示
      return utcTime;
    } catch (e) {
      debugPrint('解析 RFC 2822 日期失败: $dateStr, 错误: $e');
      return null;
    }
  }

  /// 从 Received 头中解析日期
  ///
  /// [receivedHeader] Received 头内容
  /// 返回解析出的日期，解析失败返回 null
  DateTime? _parseReceivedHeaderDate(String? receivedHeader) {
    if (receivedHeader == null || receivedHeader.isEmpty) {
      return null;
    }

    // Received 头格式: ...; Sun, 19 Apr 2026 15:28:05 +0800
    // 日期位于最后一个分号之后
    final dateRegex = RegExp(
      r';\s*((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),?\s+\d{1,2}\s+'
      r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+'
      r'\d{4}\s+\d{2}:\d{2}:\d{2}\s+[+-]\d{4})',
      caseSensitive: true,
    );

    final match = dateRegex.firstMatch(receivedHeader);
    if (match == null) {
      debugPrint('Received 头日期格式不匹配: $receivedHeader');
      return null;
    }

    final dateStr = match.group(1);
    if (dateStr == null) {
      return null;
    }

    try {
      // 解析 RFC 2822 日期格式: Sun, 19 Apr 2026 15:28:05 +0800
      final parsed = _parseRfc2822Date(dateStr);
      if (parsed != null) {
        debugPrint('从 Received 头解析日期成功: $parsed');
        return parsed;
      }
    } catch (e) {
      debugPrint('解析 Received 头日期失败: $e');
    }

    return null;
  }

  /// 从邮件消息中提取日期（带降级策略）
  ///
  /// 优先级: Date 头 > Received 头 > 当前时间
  /// [message] MIME 消息对象
  /// 返回解析出的日期
  DateTime _extractDateFromMessage(MimeMessage message) {
    // 优先级 1: 尝试从 Date 头获取
    try {
      final date = message.decodeDate();
      if (date != null && date.year != 1970) {
        debugPrint('邮件 ${message.sequenceId} 从 Date 头获取日期: $date');
        return date;
      }
    } catch (e) {
      debugPrint('解析 Date 头异常: $e');
    }

    // 优先级 2: 尝试从 Received 头获取
    final headers = message.headers;
    if (headers != null) {
      final receivedHeaders = headers
          .where((h) => h.lowerCaseName == 'received')
          .toList();

      // 从最后一个 Received 头开始尝试（最后一个是最接近接收时间的）
      for (var i = receivedHeaders.length - 1; i >= 0; i--) {
        final receivedDate = _parseReceivedHeaderDate(receivedHeaders[i].value);
        if (receivedDate != null) {
          debugPrint(
            '邮件 ${message.sequenceId} 从 Received 头获取日期: $receivedDate',
          );
          return receivedDate;
        }
      }
    }

    // 优先级 3: 使用当前时间作为兜底
    final now = DateTime.now();
    debugPrint('邮件 ${message.sequenceId} 无有效日期，使用当前时间: $now');
    return now;
  }

  /// 将 MimeMessage 转换为 Email 模型
  Email _convertToEmail(MimeMessage message) {
    // 获取邮件 ID（使用 UID，UID 在邮箱中唯一且不变）
    final id =
        message.uid?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // 获取发件人信息
    String? senderName;
    String senderEmail;

    final from = message.from;
    if (from != null && from.isNotEmpty) {
      final personalName = from.first.personalName;
      if (personalName != null && personalName.isNotEmpty) {
        senderName = personalName;
      }
      senderEmail = from.first.email;
    } else {
      senderEmail = 'unknown@unknown.com';
    }

    // 获取邮件主题
    final subject = message.decodeSubject() ?? '(无主题)';

    // 获取邮件日期（使用降级策略）
    final date = _extractDateFromMessage(message);

    // 获取邮件内容
    // 使用 MimeParser 解析邮件内容，支持 Markdown 类型
    String? preview;
    String? body;
    EmailContentType contentType = EmailContentType.unknown;
    try {
      final parser = MimeParser();
      final parseResult = parser.parseMessage(message);

      if (parseResult.success && parseResult.content != null) {
        body = parseResult.content!.content;
        contentType = parseResult.content!.type;
        preview = _extractPreviewText(body);
        debugPrint('MimeParser 解析成功，内容类型: $contentType, 长度: ${body.length}');
      } else {
        debugPrint('MimeParser 解析失败: ${parseResult.errorMessage}');
        // 降级处理：使用 enough_mail 的默认方法
        final htmlPart = message.decodeTextHtmlPart();
        if (htmlPart != null) {
          body = htmlPart;
          preview = _extractPreviewText(htmlPart);
          contentType = EmailContentType.html;
        } else {
          final textPart = message.decodeTextPlainPart();
          if (textPart != null) {
            body = textPart;
            preview = _extractPreviewText(textPart);
            contentType = EmailContentType.plainText;
          }
        }
      }
    } catch (e) {
      debugPrint('解析邮件内容失败: $e');
    }

    // 检查是否已读（有 \Seen 标志表示已读）
    final isRead = message.hasFlag(MessageFlags.seen);

    // 保存原始 MIME 内容（用于 MimeMessageViewer 渲染）
    final mimeMessageRaw = message.renderMessage();

    return Email(
      id: id,
      senderName: senderName,
      senderEmail: senderEmail,
      subject: subject,
      date: date,
      preview: preview,
      body: body,
      contentType: contentType,
      isRead: isRead,
      mimeMessageRaw: mimeMessageRaw,
    );
  }

  /// 获取单封邮件详情
  ///
  /// [config] IMAP 配置信息
  /// [messageId] 邮件 UID
  /// [mailbox] 邮箱文件夹名称，默认为 INBOX
  Future<Email> fetchEmailDetail({
    required ImapConfig config,
    required String messageId,
    String mailbox = 'INBOX',
  }) async {
    try {
      // 确保已连接
      await connect(config);

      // 选择邮箱文件夹
      await _client!.selectMailboxByPath(mailbox);

      // 根据邮件 UID 获取邮件
      final uid = int.tryParse(messageId);
      if (uid == null) {
        throw EmailServiceException(
          '无效的邮件 UID',
          errorType: EmailServiceErrorType.parseError,
        );
      }

      // 使用 UID 获取邮件（使用 BODY[] 而非 BODY.PEEK[]，自动触发 \Seen 标志）
      final fetchResult = await _client!.uidFetchMessage(uid, '(FLAGS BODY[])');

      if (fetchResult.messages.isEmpty) {
        throw EmailServiceException(
          '邮件不存在',
          errorType: EmailServiceErrorType.parseError,
        );
      }

      // 转换为 Email 模型
      return _convertToEmail(fetchResult.messages.first);
    } on EmailServiceException {
      rethrow;
    } catch (e) {
      throw EmailServiceException(
        '获取邮件详情失败: $e',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    }
  }

  /// 标记邮件为已读
  ///
  /// [config] IMAP 配置信息
  /// [messageId] 邮件 UID
  /// [mailbox] 邮箱文件夹名称，默认为 INBOX
  Future<void> markAsRead({
    required ImapConfig config,
    required String messageId,
    String mailbox = 'INBOX',
  }) async {
    try {
      // 确保已连接
      await connect(config);

      // 选择邮箱文件夹
      await _client!.selectMailboxByPath(mailbox);

      // 根据邮件 UID 标记为已读
      final uid = int.tryParse(messageId);
      if (uid == null) {
        throw EmailServiceException(
          '无效的邮件 UID',
          errorType: EmailServiceErrorType.parseError,
        );
      }

      // 使用 UID 标记为已读
      await _client!.uidStore(MessageSequence.fromId(uid), [
        MessageFlags.seen,
      ], action: StoreAction.add);
    } on EmailServiceException {
      rethrow;
    } catch (e) {
      throw EmailServiceException(
        '标记邮件已读失败: $e',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    }
  }

  /// 判断是否是腾讯企业邮箱（企业微信邮箱）
  ///
  /// 腾讯企业邮箱的 IMAP 服务器通常是 imap.exmail.qq.com
  bool _isTencentExmail(ImapConfig config) {
    final server = config.server.toLowerCase();
    return server.contains('exmail.qq.com') || server.contains('exmail');
  }

  /// 列出所有邮箱文件夹
  ///
  /// [config] IMAP 配置信息
  /// 返回邮箱文件夹列表
  Future<List<Mailbox>> listMailboxes({required ImapConfig config}) async {
    try {
      // 确保已连接
      await connect(config);

      // 列出所有邮箱文件夹
      final mailboxes = await _client!.listMailboxes(recursive: true);

      debugPrint('找到 ${mailboxes.length} 个邮箱文件夹');
      for (final mailbox in mailboxes) {
        debugPrint(
          '  - ${mailbox.name} (path: ${mailbox.path}, flags: ${mailbox.flags})',
        );
      }

      return mailboxes;
    } catch (e) {
      debugPrint('列出邮箱文件夹失败: $e');
      rethrow;
    }
  }

  /// 查找"已删除"文件夹
  ///
  /// [config] IMAP 配置信息
  /// 返回"已删除"文件夹的路径，如果找不到则返回 null
  Future<String?> findTrashMailbox({required ImapConfig config}) async {
    try {
      final mailboxes = await listMailboxes(config: config);

      // 常见的"已删除"文件夹名称（按优先级排序）
      final trashNames = [
        '已删除',
        'Deleted Messages',
        'Deleted',
        'Trash',
        '垃圾邮件',
        'Junk',
        'Spam',
      ];

      for (final name in trashNames) {
        for (final mailbox in mailboxes) {
          if (mailbox.name.toLowerCase() == name.toLowerCase() ||
              mailbox.path.toLowerCase() == name.toLowerCase()) {
            debugPrint('找到已删除文件夹: ${mailbox.path}');
            return mailbox.path;
          }
        }
      }

      // 如果找不到，尝试查找包含 \Trash 标志的文件夹
      for (final mailbox in mailboxes) {
        if (mailbox.flags.contains(MailboxFlag.trash)) {
          debugPrint('找到已删除文件夹(通过标志): ${mailbox.path}');
          return mailbox.path;
        }
      }

      debugPrint('未找到已删除文件夹');
      return null;
    } catch (e) {
      debugPrint('查找已删除文件夹失败: $e');
      return null;
    }
  }

  /// 移动邮件到指定文件夹
  ///
  /// [config] IMAP 配置信息
  /// [messageId] 邮件 UID
  /// [targetMailbox] 目标邮箱文件夹名称
  /// [mailbox] 当前邮箱文件夹名称，默认为 INBOX
  Future<void> moveEmail({
    required ImapConfig config,
    required String messageId,
    required String targetMailbox,
    String mailbox = 'INBOX',
  }) async {
    try {
      // 确保已连接
      await connect(config);

      // 选择邮箱文件夹
      await _client!.selectMailboxByPath(mailbox);

      // 解析邮件 UID
      final uid = int.tryParse(messageId);
      if (uid == null) {
        throw EmailServiceException(
          '无效的邮件 UID',
          errorType: EmailServiceErrorType.parseError,
        );
      }

      // 检查服务器是否支持 MOVE 扩展
      final capabilities = _client!.serverInfo.capabilities;
      if (capabilities == null ||
          !capabilities.any((cap) => cap.name == 'MOVE')) {
        throw EmailServiceException(
          '服务器不支持 MOVE 命令',
          errorType: EmailServiceErrorType.unknown,
        );
      }

      // 使用 UID MOVE 移动邮件
      await _client!.uidMove(
        MessageSequence.fromId(uid),
        targetMailboxPath: targetMailbox,
      );

      debugPrint('邮件 $messageId 已移动到 $targetMailbox');
    } on EmailServiceException {
      rethrow;
    } on SocketException catch (e) {
      throw EmailServiceException(
        '网络连接失败: ${e.message}',
        errorType: EmailServiceErrorType.networkError,
        originalError: e,
      );
    } on TimeoutException catch (e) {
      throw EmailServiceException(
        '操作超时: ${e.message}',
        errorType: EmailServiceErrorType.timeoutError,
        originalError: e,
      );
    } on ImapException catch (e) {
      // 检查是否是连接断开
      if (_client != null && !_client!.isConnected) {
        throw EmailServiceException(
          'IMAP 连接已断开',
          errorType: EmailServiceErrorType.connectionLost,
          originalError: e,
        );
      }

      throw EmailServiceException(
        '移动邮件失败: ${e.message}',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    } catch (e) {
      throw EmailServiceException(
        '移动邮件失败: $e',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    }
  }

  /// 删除邮件
  ///
  /// [config] IMAP 配置信息
  /// [messageId] 邮件 UID
  /// [mailbox] 邮箱文件夹名称，默认为 INBOX
  ///
  /// 删除策略：
  /// - 腾讯企业邮箱：使用 MOVE 命令将邮件移动到"已删除"文件夹
  /// - 其他邮箱：标记为 \Deleted 后执行 expunge 永久删除
  Future<void> deleteEmail({
    required ImapConfig config,
    required String messageId,
    String mailbox = 'INBOX',
  }) async {
    try {
      // 腾讯企业邮箱使用移动方式删除
      if (_isTencentExmail(config)) {
        debugPrint('检测到腾讯企业邮箱，使用移动方式删除');

        // 动态查找"已删除"文件夹
        final trashMailbox = await findTrashMailbox(config: config);
        if (trashMailbox == null) {
          throw EmailServiceException(
            '未找到"已删除"文件夹，无法删除邮件',
            errorType: EmailServiceErrorType.unknown,
          );
        }

        debugPrint('使用已删除文件夹: $trashMailbox');
        await moveEmail(
          config: config,
          messageId: messageId,
          targetMailbox: trashMailbox,
          mailbox: mailbox,
        );
        return;
      }

      // 确保已连接
      await connect(config);

      // 选择邮箱文件夹
      await _client!.selectMailboxByPath(mailbox);

      // 解析邮件 UID
      final uid = int.tryParse(messageId);
      if (uid == null) {
        throw EmailServiceException(
          '无效的邮件 UID',
          errorType: EmailServiceErrorType.parseError,
        );
      }

      // 使用 UID 标记邮件为删除
      await _client!.uidStore(MessageSequence.fromId(uid), [
        MessageFlags.deleted,
      ], action: StoreAction.add);

      // 执行 expunge 永久删除
      await _client!.expunge();

      debugPrint('邮件 $messageId 已删除');
    } on EmailServiceException {
      rethrow;
    } on SocketException catch (e) {
      throw EmailServiceException(
        '网络连接失败: ${e.message}',
        errorType: EmailServiceErrorType.networkError,
        originalError: e,
      );
    } on TimeoutException catch (e) {
      throw EmailServiceException(
        '操作超时: ${e.message}',
        errorType: EmailServiceErrorType.timeoutError,
        originalError: e,
      );
    } on ImapException catch (e) {
      // 检查是否是连接断开
      if (_client != null && !_client!.isConnected) {
        throw EmailServiceException(
          'IMAP 连接已断开',
          errorType: EmailServiceErrorType.connectionLost,
          originalError: e,
        );
      }

      throw EmailServiceException(
        '删除邮件失败: ${e.message}',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    } catch (e) {
      throw EmailServiceException(
        '删除邮件失败: $e',
        errorType: EmailServiceErrorType.unknown,
        originalError: e,
      );
    }
  }
}
