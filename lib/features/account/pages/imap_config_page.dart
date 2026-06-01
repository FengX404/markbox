import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../pages/email_list_page.dart';
import '../../../shared/models/imap_config.dart';
import '../../../shared/providers/account_config_provider.dart';
import '../../../shared/services/imap_service.dart';
import '../../../shared/themes/app_colors.dart';
import '../../../shared/themes/app_text_styles.dart';
import '../../../shared/themes/app_spacing.dart';
import '../../../shared/widgets/animated_widgets.dart';
import '../../../shared/routes/animated_page_route.dart';

/// IMAP 配置页面
///
/// 用于配置和测试 IMAP 邮箱连接
/// 支持新建、预设配置和编辑模式
class ImapConfigPage extends ConsumerStatefulWidget {
  /// 可选的现有配置，用于编辑模式或预设配置模式
  final ImapConfig? config;

  /// 是否为编辑模式
  final bool isEditMode;

  const ImapConfigPage({super.key, this.config, this.isEditMode = false});

  /// 是否为预设配置模式（配置存在但邮箱为空）
  bool get isPresetMode => config != null && config!.email.isEmpty;

  @override
  ConsumerState<ImapConfigPage> createState() => _ImapConfigPageState();
}

class _ImapConfigPageState extends ConsumerState<ImapConfigPage> {
  // 表单全局 Key
  final _formKey = GlobalKey<FormState>();

  // 文本编辑控制器
  final _serverController = TextEditingController();
  final _portController = TextEditingController(text: '993'); // 默认 IMAP SSL 端口
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  // 是否显示密码
  bool _obscurePassword = true;

  // 是否测试成功
  bool _testSuccess = false;

  // 是否正在测试连接
  bool _isTesting = false;

  // 是否使用 SSL
  bool _useSSL = true;

  // IMAP 服务实例
  final ImapService _imapService = ImapService();

  @override
  void initState() {
    super.initState();
    // 如果传入了配置，则预填充表单
    if (widget.config != null) {
      _loadConfig(widget.config!);
    }
  }

  /// 加载配置到表单
  void _loadConfig(ImapConfig config) {
    _serverController.text = config.server;
    _portController.text = config.port.toString();
    _emailController.text = config.email;
    _useSSL = config.useSSL;
    _displayNameController.text = config.displayName ?? '';
    // 密码不预填充，需要用户重新输入
  }

  @override
  void dispose() {
    _serverController.dispose();
    _portController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  /// 验证服务器地址
  String? _validateServer(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入服务器地址';
    }
    return null;
  }

  /// 验证端口号
  String? _validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入端口号';
    }
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      return '端口号必须在 1-65535 之间';
    }
    return null;
  }

  /// 验证邮箱地址
  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入邮箱地址';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,24}$');
    if (!emailRegex.hasMatch(value)) {
      return '请输入有效的邮箱地址';
    }
    return null;
  }

  /// 验证授权码
  String? _validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入授权码';
    }
    return null;
  }

  /// 测试连接
  Future<void> _testConnection() async {
    // 先验证表单
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 设置测试状态
    setState(() {
      _isTesting = true;
      _testSuccess = false;
    });

    // 创建配置对象
    final config = _buildConfig();

    try {
      // 调用 IMAP 服务测试连接
      final result = await _imapService.testConnectionWithValidation(config);

      if (mounted) {
        if (result.success) {
          // 测试成功，更新状态
          setState(() {
            _testSuccess = true;
          });
          // 成功状态已通过 UI 反馈（绿色卡片），无需额外通知
        } else {
          // 测试失败，显示错误提示
          _showSnackBar(result.errorMessage ?? '连接测试失败', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('测试连接时发生错误: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  /// 构建配置对象
  ImapConfig _buildConfig() {
    return ImapConfig(
      id: widget.config?.id ?? _generateId(),
      server: _serverController.text.trim(),
      port: int.parse(_portController.text.trim()),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      useSSL: _useSSL,
      displayName: _displayNameController.text.trim().isEmpty
          ? null
          : _displayNameController.text.trim(),
      createdAt:
          widget.config?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 生成唯一 ID（使用 UUID v4）
  String _generateId() {
    return const Uuid().v4();
  }

  /// 保存配置
  Future<void> _saveConfig() async {
    // 先验证表单
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 创建配置对象
    final config = _buildConfig();

    // 根据模式选择保存或更新
    bool success;
    if (widget.isEditMode) {
      // 编辑模式：更新配置
      success = await ref
          .read(accountConfigProvider.notifier)
          .updateConfig(config);
    } else {
      // 新建模式：添加配置
      success = await ref
          .read(accountConfigProvider.notifier)
          .addConfig(config);
    }

    if (mounted) {
      if (success) {
        // 保存成功后跳转到邮件列表页面，清除导航栈
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              SlideFadePageRoute(page: const EmailListPage()),
              (route) => false,
            );
          }
        });
      } else {
        // 获取错误信息
        final error = ref.read(accountConfigProvider).error;
        _showSnackBar(error ?? '保存配置失败', isError: true);
      }
    }
  }

  /// 显示提示消息
  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听账户配置状态
    final configState = ref.watch(accountConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getPageTitle()),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: AppEdgeInsets.page,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 说明文字
              FadeInWidget(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: AppEdgeInsets.card,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '配置说明',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请填写您的邮箱 IMAP 服务器信息。授权码需要从邮箱设置中获取，不是邮箱登录密码。',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 显示名称输入框（可选）
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: '显示名称（可选）',
                  hintText: '例如: 工作邮箱',
                  prefixIcon: const Icon(Icons.label_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // 服务器地址输入框
              TextFormField(
                controller: _serverController,
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: '例如: imap.qq.com',
                  prefixIcon: const Icon(Icons.dns),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                validator: _validateServer,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _resetTestState(),
              ),
              const SizedBox(height: 16),

              // 端口号输入框
              TextFormField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: '端口号',
                  hintText: '例如: 993',
                  prefixIcon: const Icon(Icons.settings_ethernet),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                validator: _validatePort,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _resetTestState(),
              ),
              const SizedBox(height: 16),

              // SSL 开关
              Card(
                child: SwitchListTile(
                  title: const Text('使用 SSL 加密'),
                  subtitle: Text(
                    _useSSL ? '已启用安全连接' : '未启用安全连接（不推荐）',
                    style: TextStyle(
                      color: _useSSL
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  value: _useSSL,
                  onChanged: (value) {
                    setState(() {
                      _useSSL = value;
                      // 自动更新端口号
                      _portController.text = value ? '993' : '143';
                      _resetTestState();
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 邮箱账号输入框
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: '邮箱账号',
                  hintText: '例如: example@qq.com',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                validator: _validateEmail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _resetTestState(),
              ),
              const SizedBox(height: 16),

              // 授权码输入框
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '授权码',
                  hintText: '请输入邮箱授权码',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                validator: _validatePassword,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onChanged: (_) => _resetTestState(),
              ),
              const SizedBox(height: 32),

              // 测试连接按钮
              FilledButton.tonal(
                onPressed: _isTesting ? null : _testConnection,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: _isTesting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('测试连接'),
                ),
              ),
              const SizedBox(height: 12),

              // 保存按钮
              FilledButton(
                onPressed: (_testSuccess && !configState.isSaving)
                    ? _saveConfig
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: configState.isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget.isEditMode ? '更新配置' : '保存配置'),
                ),
              ),
              const SizedBox(height: 16),

              // 测试状态提示
              if (_testSuccess)
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '连接测试成功，可以保存配置',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 重置测试状态
  void _resetTestState() {
    if (_testSuccess) {
      setState(() {
        _testSuccess = false;
      });
    }
  }

  /// 获取页面标题
  String _getPageTitle() {
    if (widget.isEditMode) {
      return '编辑邮箱';
    } else if (widget.isPresetMode) {
      return '配置邮箱';
    } else {
      return '添加邮箱';
    }
  }
}
