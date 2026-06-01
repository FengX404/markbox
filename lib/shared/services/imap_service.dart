import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';

import '../models/imap_config.dart';
import '../models/imap_connection_result.dart';

/// IMAP 连接服务
///
/// 提供邮箱 IMAP 连接测试功能，使用单例模式
class ImapService {
  // 单例实例
  static final ImapService _instance = ImapService._internal();

  /// 获取单例实例
  factory ImapService() => _instance;

  // 私有构造函数
  ImapService._internal();

  /// 连接超时时间（毫秒）
  static const int connectionTimeoutMs = 10000;

  /// 测试 IMAP 连接
  ///
  /// [config] IMAP 配置信息
  /// 返回连接结果，包含成功状态和错误信息
  Future<ImapConnectionResult> testConnection(ImapConfig config) async {
    final client = ImapClient(isLogEnabled: kDebugMode);

    try {
      debugPrint('开始测试 IMAP 连接: ${config.server}:${config.port}');

      // 连接到服务器（使用超时控制）
      await client
          .connectToServer(config.server, config.port, isSecure: config.useSSL)
          .timeout(
            const Duration(milliseconds: connectionTimeoutMs),
            onTimeout: () {
              throw TimeoutException('连接超时');
            },
          );

      debugPrint('IMAP 服务器连接成功');

      // 登录认证
      await client.login(config.email, config.password);

      debugPrint('IMAP 认证成功');

      // 检查服务器能力
      final capabilities = await client.capability();
      debugPrint('IMAP 服务器能力: $capabilities');

      // 登出
      try {
        await client.logout();
      } catch (e) {
        debugPrint('IMAP 登出时出错: $e');
      }

      debugPrint('IMAP 连接测试成功');
      return ImapConnectionResult.success();
    } on SocketException catch (e) {
      debugPrint('网络错误: ${e.message}');
      return ImapConnectionResult.failure(
        errorMessage: '网络连接失败: ${e.message}',
        errorType: ImapErrorType.networkError,
      );
    } on TimeoutException catch (e) {
      debugPrint('连接超时: ${e.message}');
      return ImapConnectionResult.failure(
        errorMessage: '连接超时: ${e.message}',
        errorType: ImapErrorType.timeoutError,
      );
    } on HandshakeException catch (e) {
      debugPrint('SSL 握手失败: ${e.message}');
      return ImapConnectionResult.failure(
        errorMessage: 'SSL 证书验证失败: ${e.message}',
        errorType: ImapErrorType.sslError,
      );
    } on TlsException catch (e) {
      debugPrint('TLS 异常: ${e.message}');
      return ImapConnectionResult.failure(
        errorMessage: 'TLS 连接失败: ${e.message}',
        errorType: ImapErrorType.sslError,
      );
    } on ImapException catch (e) {
      debugPrint('IMAP 协议错误: ${e.message}');

      // 根据错误消息判断具体错误类型
      final errorMessage = e.message?.toLowerCase() ?? '';
      if (errorMessage.contains('authentication') ||
          errorMessage.contains('login') ||
          errorMessage.contains('credentials') ||
          errorMessage.contains('invalid') ||
          errorMessage.contains('denied')) {
        return ImapConnectionResult.failure(
          errorMessage: '认证失败: ${e.message}',
          errorType: ImapErrorType.authenticationFailed,
        );
      }

      if (errorMessage.contains('capability') ||
          errorMessage.contains('not supported')) {
        return ImapConnectionResult.failure(
          errorMessage: '服务器不支持 IMAP: ${e.message}',
          errorType: ImapErrorType.serverNotSupported,
        );
      }

      return ImapConnectionResult.failure(
        errorMessage: 'IMAP 协议错误: ${e.message}',
        errorType: ImapErrorType.unknown,
      );
    } catch (e) {
      debugPrint('未知错误: $e');
      return ImapConnectionResult.failure(
        errorMessage: '发生未知错误: $e',
        errorType: ImapErrorType.unknown,
      );
    } finally {
      // 确保断开连接
      try {
        if (client.isConnected) {
          await client.disconnect();
        }
      } catch (e) {
        debugPrint('断开连接时出错: $e');
      }
      try {
        client.close();
      } catch (e) {
        debugPrint('关闭 IMAP 客户端时出错: $e');
      }
    }
  }

  /// 验证 IMAP 配置参数
  ///
  /// [config] IMAP 配置信息
  /// 返回验证结果，如果验证失败则包含错误信息
  ImapConnectionResult? validateConfig(ImapConfig config) {
    // 检查服务器地址
    if (config.server.isEmpty) {
      return ImapConnectionResult.failure(
        errorMessage: '服务器地址不能为空',
        errorType: ImapErrorType.networkError,
      );
    }

    // 检查端口号
    if (config.port <= 0 || config.port > 65535) {
      return ImapConnectionResult.failure(
        errorMessage: '端口号无效，必须在 1-65535 之间',
        errorType: ImapErrorType.networkError,
      );
    }

    // 检查邮箱地址
    if (config.email.isEmpty) {
      return ImapConnectionResult.failure(
        errorMessage: '邮箱地址不能为空',
        errorType: ImapErrorType.authenticationFailed,
      );
    }

    // 简单验证邮箱格式
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,24}$');
    if (!emailRegex.hasMatch(config.email)) {
      return ImapConnectionResult.failure(
        errorMessage: '邮箱地址格式不正确',
        errorType: ImapErrorType.authenticationFailed,
      );
    }

    // 检查密码/授权码
    if (config.password.isEmpty) {
      return ImapConnectionResult.failure(
        errorMessage: '授权码不能为空',
        errorType: ImapErrorType.authenticationFailed,
      );
    }

    return null; // 验证通过
  }

  /// 测试连接（带配置验证）
  ///
  /// [config] IMAP 配置信息
  /// 返回连接结果
  Future<ImapConnectionResult> testConnectionWithValidation(
    ImapConfig config,
  ) async {
    // 先验证配置参数
    final validationResult = validateConfig(config);
    if (validationResult != null) {
      return validationResult;
    }

    // 验证通过后测试连接
    return testConnection(config);
  }
}
