import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/email_list_state.dart';
import '../models/email.dart';
import '../models/imap_config.dart';
import '../models/summary_status.dart';
import '../../services/email_service.dart';
import '../../services/zhipu_service.dart';
import '../services/secure_storage_service.dart';
import 'account_config_provider.dart';
import 'api_key_provider.dart';

part 'email_list_provider.g.dart';

/// 邮件服务 Provider
///
/// 提供 EmailService 的单例实例
@riverpod
EmailService emailService(EmailServiceRef ref) {
  return EmailService();
}

/// 智谱服务 Provider
///
/// 提供 ZhipuService 的单例实例
@riverpod
ZhipuService zhipuService(ZhipuServiceRef ref) {
  return ZhipuService();
}

/// 邮件列表 Provider
///
/// 管理邮件列表的状态，包括加载、刷新、分页等操作
/// keepAlive: true 保持状态不被自动释放，实现内存缓存
@Riverpod(keepAlive: true)
class EmailList extends _$EmailList {
  /// 邮件服务实例
  late final EmailService _emailService;

  /// 智谱服务实例
  late final ZhipuService _zhipuService;

  /// 安全存储服务实例
  late final SecureStorageService _storageService;

  /// 每页邮件数量
  static const int pageSize = 50;

  /// 自动刷新定时器
  Timer? _autoRefreshTimer;

  /// 自动刷新间隔（秒）
  static const int autoRefreshIntervalSeconds = 30;

  @override
  EmailListState build() {
    // 初始化服务实例
    _emailService = ref.watch(emailServiceProvider);
    _zhipuService = ref.watch(zhipuServiceProvider);
    _storageService = SecureStorageService();

    // 注册资源清理回调
    ref.onDispose(() {
      _stopAutoRefresh();
      _emailService.disconnect();
    });

    // 在 build 返回后异步加载缓存
    Future.microtask(() => _loadCachedEmails());

    // 返回初始状态
    return const EmailListState();
  }

  /// 从本地存储加载缓存的邮件列表
  ///
  /// 如果有缓存数据，直接显示并标记为已初始化
  Future<void> _loadCachedEmails() async {
    try {
      final cachedEmails = await _storageService.loadEmailList();
      if (cachedEmails.isNotEmpty) {
        state = state.copyWith(emails: cachedEmails, isInitialized: true);
      }
    } catch (e) {
      // 加载缓存失败时忽略，继续正常加载
      debugPrint('加载缓存失败: $e');
    }
  }

  /// 启动自动刷新定时器
  ///
  /// 每隔 [autoRefreshIntervalSeconds] 秒执行一次静默刷新
  void _startAutoRefresh() {
    _stopAutoRefresh();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: autoRefreshIntervalSeconds),
      (_) => silentRefresh(),
    );
    debugPrint('自动刷新已启动，间隔 ${autoRefreshIntervalSeconds}s');
  }

  /// 停止自动刷新定时器
  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// 保存邮件列表到本地存储
  Future<void> _saveEmailsToCache(List<Email> emails) async {
    try {
      await _storageService.saveEmailList(emails);
    } catch (_) {
      // 保存失败时忽略，不影响用户体验
    }
  }

  /// 加载邮件列表（首次加载）
  ///
  /// 从所有已配置的 IMAP 账户获取邮件
  /// 如果没有配置账户，会设置错误信息
  Future<void> loadEmails() async {
    // 获取当前账户配置列表
    final accountConfig = ref.read(accountConfigProvider);
    final configs = accountConfig.configs;

    // 检查是否有配置
    if (configs.isEmpty) {
      state = state.copyWith(error: '未配置邮箱账户', isLoading: false);
      return;
    }

    // 设置加载状态
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 从所有账户获取邮件
      final allEmails = await _fetchEmailsFromAllAccounts(configs);

      // 合并并按时间排序
      final sortedEmails = _mergeAndSortEmails(allEmails);

      // 更新状态
      state = state.copyWith(
        emails: sortedEmails,
        isLoading: false,
        isInitialized: true,
        currentPage: 1,
        hasMore: sortedEmails.length >= pageSize,
        totalCount: sortedEmails.length,
        error: null,
      );

      // 保存到本地存储
      await _saveEmailsToCache(sortedEmails);

      // 启动自动刷新
      _startAutoRefresh();

      // 异步生成摘要
      _generateSummaries(sortedEmails);
    } on EmailServiceException catch (e) {
      // 处理邮件服务异常
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      // 处理其他异常
      state = state.copyWith(isLoading: false, error: '加载邮件失败: $e');
    }
  }

  /// 从所有账户获取邮件
  ///
  /// [configs] IMAP 配置列表
  /// 返回所有账户的邮件列表
  /// 注意：由于 EmailService 使用单例连接，必须顺序获取每个账户的邮件
  Future<List<Email>> _fetchEmailsFromAllAccounts(List<ImapConfig> configs, {int page = 1}) async {
    final allEmails = <Email>[];

    // 顺序获取每个账户的邮件（避免连接冲突）
    for (final config in configs) {
      try {
        final result = await _emailService.fetchEmails(
          config: config,
          page: page,
          pageSize: pageSize,
        );
        allEmails.addAll(result.emails);
        debugPrint('成功获取 ${result.emails.length} 封邮件 (${config.email}, 第$page页)');
      } catch (e) {
        debugPrint('获取邮件失败 (${config.email}): $e');
        // 继续获取下一个账户的邮件
      }
    }

    return allEmails;
  }

  /// 合并并按时间排序邮件
  ///
  /// [emails] 邮件列表
  /// 返回去重并按时间降序排序的邮件列表
  List<Email> _mergeAndSortEmails(List<Email> emails) {
    // 去重（使用邮件 ID）
    final emailMap = <String, Email>{};
    for (final email in emails) {
      emailMap[email.id] = email;
    }

    // 按时间降序排序
    final sortedEmails = emailMap.values.toList();
    sortedEmails.sort((a, b) => b.date.compareTo(a.date));

    return sortedEmails;
  }

  /// 静默刷新（后台增量更新）
  ///
  /// 用于已缓存数据时，后台获取新邮件并合并到列表顶部
  /// 不会显示全屏加载状态，失败时保持原有数据
  Future<void> silentRefresh() async {
    // 如果正在刷新或加载，不重复执行
    if (state.isRefreshing || state.isLoading) {
      return;
    }

    // 获取当前账户配置列表
    final accountConfig = ref.read(accountConfigProvider);
    final configs = accountConfig.configs;

    // 检查是否有配置
    if (configs.isEmpty) {
      return;
    }

    // 设置静默刷新状态（不显示全屏加载）
    state = state.copyWith(isRefreshing: true);

    try {
      // 从所有账户获取邮件
      final allEmails = await _fetchEmailsFromAllAccounts(configs);

      // 合并新邮件到现有列表（去重）
      final mergedEmails = _mergeEmails(
        newEmails: allEmails,
        existingEmails: state.emails,
      );

      // 找出新邮件（用于生成摘要）
      final existingIds = state.emails.map((e) => e.id).toSet();
      final newEmails = allEmails
          .where((e) => !existingIds.contains(e.id))
          .toList();

      // 更新状态
      state = state.copyWith(
        emails: mergedEmails,
        isRefreshing: false,
        isInitialized: true,
        totalCount: mergedEmails.length,
        error: null,
      );

      // 保存到本地存储
      await _saveEmailsToCache(mergedEmails);

      // 异步生成摘要（只对新邮件生成）
      if (newEmails.isNotEmpty) {
        _generateSummaries(newEmails);
      }
    } on EmailServiceException {
      // 静默刷新失败，保持原有数据，只更新状态
      state = state.copyWith(isRefreshing: false);
    } catch (_) {
      // 静默刷新失败，保持原有数据
      state = state.copyWith(isRefreshing: false);
    }
  }

  /// 合并邮件列表（去重并排序）
  ///
  /// 将新邮件合并到现有列表，去除重复邮件后统一按时间降序排序
  List<Email> _mergeEmails({
    required List<Email> newEmails,
    required List<Email> existingEmails,
  }) {
    // 创建现有邮件 ID 集合，用于快速查找
    final existingIds = existingEmails.map((e) => e.id).toSet();

    // 过滤出新邮件（不在现有列表中的）
    final uniqueNewEmails = newEmails
        .where((e) => !existingIds.contains(e.id))
        .toList();

    // 如果没有新邮件，直接返回原列表
    if (uniqueNewEmails.isEmpty) {
      return existingEmails;
    }

    // 合并邮件列表
    final mergedEmails = [...uniqueNewEmails, ...existingEmails];

    // 统一按时间降序排序（新的在上面）
    mergedEmails.sort((a, b) => b.date.compareTo(a.date));

    return mergedEmails;
  }

  /// 刷新邮件列表（下拉刷新）
  ///
  /// 重新获取所有账户的邮件数据，清空现有列表
  Future<void> refreshEmails() async {
    // 获取当前账户配置列表
    final accountConfig = ref.read(accountConfigProvider);
    final configs = accountConfig.configs;

    // 检查是否有配置
    if (configs.isEmpty) {
      state = state.copyWith(error: '未配置邮箱账户', isRefreshing: false);
      return;
    }

    // 设置刷新状态
    state = state.copyWith(isRefreshing: true, error: null);

    try {
      // 从所有账户获取邮件
      final allEmails = await _fetchEmailsFromAllAccounts(configs);

      // 合并并按时间排序
      final sortedEmails = _mergeAndSortEmails(allEmails);

      // 创建本地摘要状态映射（保留已生成的摘要）
      final localSummaryMap =
          <String, (String? summary, SummaryStatus status)>{};
      for (final email in state.emails) {
        if (email.summaryStatus == SummaryStatus.generated ||
            email.summaryStatus == SummaryStatus.generating) {
          localSummaryMap[email.id] = (email.summary, email.summaryStatus);
        }
      }

      // 合并本地摘要状态到新邮件列表
      final mergedEmails = sortedEmails.map((email) {
        final localData = localSummaryMap[email.id];
        if (localData != null) {
          return email.copyWith(
            summary: localData.$1,
            summaryStatus: localData.$2,
          );
        }
        return email;
      }).toList();

      // 更新状态
      state = state.copyWith(
        emails: mergedEmails,
        isRefreshing: false,
        isInitialized: true,
        currentPage: 1,
        hasMore: false,
        totalCount: mergedEmails.length,
        error: null,
      );

      // 保存到本地存储
      await _saveEmailsToCache(mergedEmails);

      // 启动自动刷新（确保刷新后定时器继续运行）
      _startAutoRefresh();

      // 异步生成摘要（只对未生成的邮件）
      _generateSummaries(mergedEmails);
    } on EmailServiceException catch (e) {
      // 处理邮件服务异常
      state = state.copyWith(isRefreshing: false, error: e.message);
    } catch (e) {
      // 处理其他异常
      state = state.copyWith(isRefreshing: false, error: '刷新邮件失败: $e');
    }
  }

  /// 加载更多邮件（分页加载）
  ///
  /// 从所有已配置账户获取下一页邮件，合并到现有列表
  Future<void> loadMoreEmails() async {
    if (!state.hasMore || state.isLoadingMore) return;

    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.currentPage + 1;

    // 获取当前账户配置列表
    final accountConfig = ref.read(accountConfigProvider);
    final configs = accountConfig.configs;

    if (configs.isEmpty) {
      state = state.copyWith(isLoadingMore: false, hasMore: false);
      return;
    }

    try {
      // 从所有账户获取下一页邮件
      final allNewEmails = await _fetchEmailsFromAllAccounts(
        configs,
        page: nextPage,
      );

      if (allNewEmails.isEmpty) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }

      // 合并新邮件到现有列表（去重、排序）
      final mergedEmails = _mergeEmails(
        newEmails: allNewEmails,
        existingEmails: state.emails,
      );

      state = state.copyWith(
        emails: mergedEmails,
        currentPage: nextPage,
        isLoadingMore: false,
        totalCount: mergedEmails.length,
      );

      // 保存到本地存储
      await _saveEmailsToCache(mergedEmails);
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: '加载更多邮件失败: $e');
    }
  }

  /// 清除错误信息
  ///
  /// 清除当前状态中的错误信息
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 标记邮件为已读
  ///
  /// [emailId] 邮件 ID
  /// 更新本地邮件列表中对应邮件的已读状态
  Future<void> markEmailAsRead(String emailId) async {
    final emails = state.emails;
    final index = emails.indexWhere((e) => e.id == emailId);

    if (index == -1) {
      return;
    }

    // 更新邮件的已读状态
    final updatedEmails = List<Email>.from(emails);
    updatedEmails[index] = updatedEmails[index].copyWith(isRead: true);

    // 更新状态
    state = state.copyWith(emails: updatedEmails);

    // 保存到本地存储
    await _saveEmailsToCache(updatedEmails);
  }

  /// 异步生成邮件摘要
  ///
  /// [emails] 需要生成摘要的邮件列表
  /// 只对未生成摘要的邮件生成摘要
  Future<void> _generateSummaries(List<Email> emails) async {
    // 获取配置
    final config = await ref.read(apiKeyProvider.notifier).loadConfig();
    if (config.apiKey == null || config.apiKey!.isEmpty) {
      return;
    }

    // 过滤出需要生成摘要的邮件（未生成状态且有内容）
    final emailsNeedSummary = emails
        .where(
          (e) =>
              e.summaryStatus == SummaryStatus.notGenerated &&
              e.body != null &&
              e.body!.isNotEmpty,
        )
        .toList();

    if (emailsNeedSummary.isEmpty) {
      return;
    }

    // 每次最多处理 5 封邮件，只将这 5 封设置为 generating 状态
    // 避免将所有待处理邮件都卡在 generating 状态
    final emailsToProcess = emailsNeedSummary.take(5).toList();
    final emailsToProcessIds = emailsToProcess.map((e) => e.id).toSet();

    // 只将实际要处理的邮件状态设置为 generating
    final generatingEmails = state.emails.map((e) {
      if (emailsToProcessIds.contains(e.id)) {
        return e.copyWith(summaryStatus: SummaryStatus.generating);
      }
      return e;
    }).toList();
    state = state.copyWith(emails: generatingEmails);

    // 保存快照，避免并发修改导致状态不一致
    final snapshotEmails = List<Email>.from(generatingEmails);

    // 创建并发任务
    final futures = emailsToProcess.map((email) async {
      try {
        final summary = await _zhipuService.generateSummary(
          apiKey: config.apiKey!,
          model: config.model,
          content: email.body!,
          maxLength: 50,
        );

        return (emailId: email.id, summary: summary, success: true);
      } catch (e) {
        debugPrint('生成摘要失败: ${email.id}, 错误: $e');
        return (emailId: email.id, summary: null, success: false);
      }
    }).toList();

    // 等待所有任务完成
    final results = await Future.wait(futures);

    // 基于快照更新邮件状态，避免与并发操作冲突
    var updatedEmails = snapshotEmails;
    for (final result in results) {
      final index = updatedEmails.indexWhere((e) => e.id == result.emailId);
      if (index != -1) {
        if (result.success && result.summary != null) {
          updatedEmails[index] = updatedEmails[index].copyWith(
            summary: result.summary,
            summaryStatus: SummaryStatus.generated,
          );
        } else {
          updatedEmails[index] = updatedEmails[index].copyWith(
            summaryStatus: SummaryStatus.failed,
          );
        }
      }
    }

    // 更新状态
    state = state.copyWith(emails: updatedEmails);

    // 保存到本地存储
    await _saveEmailsToCache(updatedEmails);
  }

  /// 删除邮件
  ///
  /// [emailId] 邮件 ID
  /// 从本地列表中移除邮件，并从服务器删除
  /// 返回是否删除成功
  Future<bool> deleteEmail(String emailId) async {
    // 获取当前账户配置列表
    final accountConfig = ref.read(accountConfigProvider);
    final configs = accountConfig.configs;

    // 检查是否有配置
    if (configs.isEmpty) {
      return false;
    }

    // 先从本地列表中移除邮件（乐观更新）
    final originalEmails = List<Email>.from(state.emails);
    final updatedEmails = originalEmails.where((e) => e.id != emailId).toList();

    // 更新本地状态
    state = state.copyWith(
      emails: updatedEmails,
      totalCount: (state.totalCount ?? 0) > 0 ? state.totalCount! - 1 : null,
    );

    try {
      // 尝试从所有账户删除邮件（邮件可能来自任意账户）
      bool deleted = false;
      for (final config in configs) {
        try {
          await _emailService.deleteEmail(config: config, messageId: emailId);
          deleted = true;
          break;
        } catch (e) {
          // 继续尝试下一个账户
          debugPrint('从账户 ${config.email} 删除邮件失败: $e');
        }
      }

      if (!deleted) {
        // 所有账户都删除失败，恢复原始列表
        state = state.copyWith(
          emails: originalEmails,
          totalCount: state.totalCount,
          error: '删除邮件失败',
        );
        return false;
      }

      // 保存到本地存储
      await _saveEmailsToCache(updatedEmails);

      debugPrint('邮件 $emailId 已删除');
      return true;
    } catch (e) {
      // 删除失败，恢复原始列表
      state = state.copyWith(
        emails: originalEmails,
        totalCount: state.totalCount,
        error: '删除邮件失败: $e',
      );

      debugPrint('删除邮件失败: $e');
      return false;
    }
  }

  /// 重置状态
  ///
  /// 将状态重置为初始状态，并停止自动刷新
  void reset() {
    _stopAutoRefresh();
    state = const EmailListState();
  }
}
