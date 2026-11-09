import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/providers/auth_provider.dart';
import 'package:task_manager/utils/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.startupError});

  final String? startupError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthProvider>().login(
        _username.text.trim(),
        _password.text,
      );
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthPage(
    title: 'Welcome back',
    subtitle: 'Sign in to manage shared tasks.',
    children: [
      if (widget.startupError != null) ...[
        _MessageBox(message: widget.startupError!),
        const SizedBox(height: 16),
      ],
      Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _username,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 14),
            _PasswordField(
              controller: _password,
              label: 'Password',
              validator: _requiredValidator,
              onSubmitted: (_) => _login(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                ),
                child: const Text('Forgot Password?'),
              ),
            ),
            const SizedBox(height: 8),
            _AuthButton(
              label: 'Login',
              isLoading: _isSubmitting,
              onPressed: _login,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen())),
        child: const Text('Create an Account / Sign Up'),
      ),
    ],
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthProvider>().register(
        name: _name.text.trim(),
        email: _email.text.trim(),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Account created. Check your email for your username and password.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthPage(
    title: 'Create your account',
    subtitle: 'Your login credentials will be emailed to you.',
    children: [
      Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 14),
            _EmailField(controller: _email),
            const SizedBox(height: 20),
            _AuthButton(
              label: 'Register',
              isLoading: _isSubmitting,
              onPressed: _register,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Already have an account? Login'),
      ),
    ],
  );
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthProvider>().forgotPassword(_email.text.trim());
      if (mounted) {
        _showMessage(
          context,
          'If an account exists for that email, a password reset link will be sent.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthPage(
    title: 'Forgot password?',
    subtitle: 'Enter your email address. We’ll email a secure reset link if an account matches.',
    children: [
      Form(
        key: _formKey,
        child: _EmailField(controller: _email),
      ),
      const SizedBox(height: 18),
      _AuthButton(
        label: 'Send reset link',
        isLoading: _isSubmitting,
        onPressed: _sendResetLink,
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back to Login'),
      ),
    ],
  );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentPassword.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await context.read<AuthProvider>().changePassword(
        currentPassword: _currentPassword.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showMessage(context, 'Password updated successfully.');
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthPage(
    title: 'Change password',
    subtitle: 'Confirm your current password before choosing a new one.',
    children: [
      Form(
        key: _formKey,
        child: Column(
          children: [
            _PasswordField(
              controller: _currentPassword,
              label: 'Current password',
              validator: _requiredValidator,
            ),
            const SizedBox(height: 14),
            _PasswordField(
              controller: _password,
              label: 'New password',
              validator: _securePasswordValidator,
            ),
            const SizedBox(height: 14),
            _PasswordField(
              controller: _confirmation,
              label: 'Confirm new password',
              validator: (value) => value != _password.text
                  ? 'Passwords do not match.'
                  : _requiredValidator(value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _AuthButton(
        label: 'Update password',
        isLoading: _isSubmitting,
        onPressed: _update,
      ),
    ],
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSigningOut = false;

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your offline tasks will stay on this device and will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSigningOut = true);
    Object? error;
    try {
      await auth.logout();
    } catch (exception) {
      error = exception;
    }
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Signed out on this device, but server logout failed: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: const Color(0xFFEAF1FF),
            child: Text(
              user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            user.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (user.username.isNotEmpty)
            Text(
              'Username: ${user.username}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          Text(
            user.email,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 26),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ChangePasswordScreen(),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.red),
            title: const Text('Sign out'),
            trailing: _isSigningOut
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _isSigningOut ? null : _logout,
          ),
        ],
      ),
    );
  }
}

class _AuthPage extends StatelessWidget {
  const _AuthPage({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFFEAF1FF),
                  child: Icon(
                    Icons.checklist_rounded,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Task Manager',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
                const SizedBox(height: 28),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.emailAddress,
    textInputAction: TextInputAction.next,
    autocorrect: false,
    autofillHints: const [AutofillHints.email],
    decoration: const InputDecoration(
      labelText: 'Email address',
      prefixIcon: Icon(Icons.email_outlined),
    ),
    validator: (value) {
      final email = value?.trim() ?? '';
      if (email.isEmpty) return 'Enter your email address.';
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        return 'Enter a valid email address.';
      }
      return null;
    },
  );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _obscure,
    textInputAction: TextInputAction.next,
    autofillHints: const [AutofillHints.password],
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
      ),
    ),
    validator: widget.validator,
    onFieldSubmitted: widget.onSubmitted,
  );
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 50,
    child: FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}

String? _requiredValidator(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;

String? _securePasswordValidator(String? value) {
  if (value == null || value.length < 12) {
    return 'Use at least 12 characters.';
  }
  if (!RegExp(r'[A-Z]').hasMatch(value) ||
      !RegExp(r'[a-z]').hasMatch(value) ||
      !RegExp(r'\d').hasMatch(value) ||
      !RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
    return 'Include uppercase, lowercase, a number, and a symbol.';
  }
  return null;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
