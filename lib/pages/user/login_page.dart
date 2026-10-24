import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../state/app_state.dart';

/// 登录页（对齐 qt LoginReq2：POST /login）。
///
/// 用户反馈：登录界面只能用账号名 + 密码登录（不能用邮箱）；找回密码
/// 只能通过邮箱，服务端会把新密码发到邮箱。两个入口分离：
/// - 「登录」按钮：仅 username + password；
/// - 「忘记密码」按钮：进入 [ForgotPasswordPage]，只填邮箱即可。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入用户名和密码')));
      return;
    }
    setState(() => _loading = true);
    final state = context.read<AppState>();
    try {
      final data = await JmApi.instance.login(u, p);
      await state.setUser(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('欢迎回来, ${data.username}')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登录失败: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 20),
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.menu_book_rounded, size: 38, color: cs.primary),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              // 仅显示「用户名」，不再含「/邮箱」
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pass,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
          const SizedBox(height: 8),
          // 「忘记密码」独立入口：进入只填邮箱的重置密码页。
          // 不再把「注册 / 忘记密码」混在一个按钮里。
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const RegisterPage()),
                ),
                child: const Text('没有账号？注册'),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ForgotPasswordPage(),
                  ),
                ),
                child: const Text('忘记密码？'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '仅用于学习研究，请使用自己拥有合法权限的账号。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

/// 找回密码页（对齐 qt ResetPasswordReq：POST /lost）。
///
/// 用户反馈：找回密码只能用邮箱，服务端会把官方生成的随机新密码发到
/// 邮箱。本页只接收邮箱字段，提交后提示用户去邮箱查看新密码。
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final e = _email.text.trim();
    if (e.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入邮箱')));
      return;
    }
    setState(() => _loading = true);
    try {
      final (ok, msg) = await JmApi.instance.resetPassword(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '新密码已发送至邮箱，请查收后用新密码登录' : '发送失败: $msg')),
      );
      if (ok) Navigator.pop(context);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败: $err')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('找回密码')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const SizedBox(height: 20),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_reset_rounded, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 22),
          Text(
            '请输入注册邮箱，官方将把新生成的随机密码发送至该邮箱。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '注册邮箱',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('发送新密码'),
          ),
        ],
      ),
    );
  }
}

/// 注册页（对齐官方 JMComic3 2.1.12 注册流程）。
///
/// 关键修复（注册无法使用）：官方 2.1.12 走 **APP API 域名 POST /register**
/// （与登录同协议，无需 Web 验证码）。旧实现走 Web 域名 /signup +
/// captcha，被 Cloudflare 拦截导致注册必然失败。
///
/// 流程对齐官方 MemberModal：
/// 1. 填写 用户名/邮箱/密码/确认密码/性别 → POST /register；
/// 2. 注册成功 → 邮箱收到验证码（numcode）→ 提交 POST /confirm 完成验证；
/// 3. 支持重发验证邮件（POST /confirm {username, password}）。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _pass2 = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _numcode = TextEditingController();
  String _gender = 'Male';
  bool _loading = false;
  bool _agree = true;

  /// 注册成功后进入邮箱验证码确认阶段。
  bool _confirmStage = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _pass2.dispose();
    _email.dispose();
    _numcode.dispose();
    super.dispose();
  }

  bool get _inputOk =>
      _user.text.trim().isNotEmpty &&
      _pass.text.isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _agree;

  Future<void> _submit() async {
    final u = _user.text.trim();
    final p = _pass.text;
    final p2 = _pass2.text;
    final e = _email.text.trim();
    if (u.isEmpty || p.isEmpty || e.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写用户名、密码和邮箱')));
      return;
    }
    if (p != p2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('两次密码不一致')));
      return;
    }
    if (!_agree) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先确认已年满 18 岁并同意条款')));
      return;
    }
    setState(() => _loading = true);
    try {
      final (ok, msg) = await JmApi.instance.register(
        u,
        e,
        p,
        p2,
        sex: _gender,
      );
      if (!mounted) return;
      if (ok) {
        // 对齐官方：注册成功 → 进入邮箱验证码确认阶段
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.isEmpty ? '注册成功，请查收验证邮件' : msg)),
        );
        setState(() => _confirmStage = true);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('注册失败: $msg')));
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('注册失败: $err')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 提交邮箱验证码完成账号验证（POST /confirm {username, numcode}）。
  Future<void> _submitNumcode() async {
    final u = _user.text.trim();
    final code = _numcode.text.trim();
    if (u.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写用户名')));
      return;
    }
    if (code.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入邮件中的验证码')));
      return;
    }
    setState(() => _loading = true);
    try {
      final (ok, msg) = await JmApi.instance.registerConfirm(u, numcode: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? (msg.isEmpty ? '验证成功，请登录' : msg) : '验证失败: $msg'),
        ),
      );
      if (ok) Navigator.pop(context);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('验证失败: $err')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 重发验证邮件（POST /confirm {username, password}，对齐官方 resend）。
  Future<void> _resendMail() async {
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先填写用户名和密码')));
      return;
    }
    setState(() => _loading = true);
    try {
      final (ok, msg) = await JmApi.instance.registerVerifyMail(u, p);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ok ? '验证邮件已发送' : msg)));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败: $err')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_confirmStage ? '邮箱验证' : '注册账号')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          if (!_confirmStage) ...<Widget>[
            // —— 注册表单（对齐官方 signUp 表单，无需验证码）——
            TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: '用户名'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '邮箱（用于接收验证码）'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pass2,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码'),
            ),
            const SizedBox(height: 16),
            // 性别选择（对齐官方 gender 字段）
            Row(
              children: <Widget>[
                const Text('性别'),
                const SizedBox(width: 16),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: 'Male',
                        label: Text('男'),
                        icon: Icon(Icons.male),
                      ),
                      ButtonSegment<String>(
                        value: 'Female',
                        label: Text('女'),
                        icon: Icon(Icons.female),
                      ),
                    ],
                    selected: <String>{_gender},
                    onSelectionChanged: (Set<String> s) =>
                        setState(() => _gender = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 成人确认 + 条款同意（对齐官方 adult / PrivacyPolicy 检查）
            CheckboxListTile(
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('我已年满 18 岁并同意相关条款'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (_loading || !_inputOk) ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('注册'),
            ),
          ] else ...<Widget>[
            // —— 邮箱验证码确认阶段（对齐官方 confirm 表单）——
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_email_read_outlined,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '注册成功！验证邮件已发送至\n${_email.text.trim()}\n请输入邮件中的验证码完成账号验证。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _numcode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '邮箱验证码',
                prefixIcon: Icon(Icons.password_rounded),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _loading ? null : _submitNumcode,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('完成验证'),
            ),
            TextButton(
              onPressed: _loading ? null : _resendMail,
              child: const Text('没收到？重新发送验证邮件'),
            ),
          ],
        ],
      ),
    );
  }
}
