import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// 智谱 AI 服务
///
/// 用于调用智谱 API 生成邮件摘要
class ZhipuService {
  /// 智谱 API 基础 URL
  static const String _baseUrl = 'https://open.bigmodel.cn/api/paas/v4';

  /// 生成邮件摘要
  ///
  /// [apiKey] 智谱 API Key
  /// [model] 模型名称，默认 glm-4-flash
  /// [content] 邮件内容
  /// [maxLength] 摘要最大长度，默认 50 字
  ///
  /// 返回生成的摘要，如果失败返回 null
  Future<String?> generateSummary({
    required String apiKey,
    String model = 'glm-4-flash',
    required String content,
    int maxLength = 50,
  }) async {
    if (content.isEmpty) {
      return null;
    }

    try {
      // 截取内容，避免过长
      final truncatedContent = content.length > 1000
          ? '${content.substring(0, 1000)}...'
          : content;

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': '''你是一个邮件摘要助手。请将邮件内容总结为不超过$maxLength个字的简短摘要。

重要规则：
1. 忽略所有格式代码（HTML标签、Markdown语法、LaTeX公式等）
2. 只提取和总结纯文本正文内容
3. 不要描述邮件的格式、样式或排版
4. 直接输出摘要内容，不要有任何前缀或解释

示例：
- 错误：该邮件包含HTML样式设置，使用了蓝色字体...
- 正确：会议定于下周五下午3点在会议室A召开...''',
            },
            {'role': 'user', 'content': '请总结以下邮件内容：\n\n$truncatedContent'},
          ],
          'max_tokens': 100,
          'temperature': 0.3,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('智谱 API 请求超时');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final summary = data['choices']?[0]?['message']?['content'] as String?;

        if (summary != null) {
          // 确保摘要不超过最大长度
          if (summary.length > maxLength) {
            return '${summary.substring(0, maxLength)}...';
          }
          return summary.trim();
        }
      } else {
        debugPrint('智谱 API 请求失败: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('生成摘要失败: $e');
    }

    return null;
  }
}
