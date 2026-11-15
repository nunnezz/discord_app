import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class _C {
  static const darkest = Color(0xFF1E1F22);
  static const bg = Color(0xFF313338);
  static const blurple = Color(0xFF5865F2);
  static const textMuted = Color(0xFF949BA4);
  static const textHeader = Color(0xFFF2F3F5);
}

/// Mesma tela de "Entrar / Criar Conta" de antes — a única mudança real
/// é QUEM valida o usuário/senha: agora é o AuthService (Supabase Auth),
/// não mais um Map local em memória. Você não precisa mais fazer nada
/// manualmente após o sucesso: o AuthGate (que escuta
/// `onAuthStateChange`) já troca de tela sozinho.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isCreatingAccount = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  static const int _minPasswordLength = 6;

  // Regex simples de formato de e-mail: algo@algo.algo — suficiente para
  // validação de UI; a validação "de verdade" (e-mail existe de fato)
  // continua sendo feita pelo próprio Supabase Auth.
  static final RegExp _emailRegex =
      RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isCreatingAccount = !_isCreatingAccount;
      _errorMessage = null;
    });
  }

  Future<void> _resendConfirmation(String email) async {
    final error = await AuthService.resendConfirmationEmail(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'E-mail de confirmação reenviado! Confira sua caixa de entrada.'),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final isFormValid = _formKey.currentState?.validate() ?? false;
    if (!isFormValid) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (password.length < _minPasswordLength) {
      setState(() =>
          _errorMessage = 'A senha deve ter no mínimo $_minPasswordLength caracteres.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final AuthResult result = _isCreatingAccount
          ? await AuthService.signUp(email: email, password: password)
          : await AuthService.signIn(email: email, password: password);

      if (!mounted) return;

      if (!result.success) {
        // Erro: mostra tanto no card vermelho quanto num SnackBar, para
        // garantir que o usuário perceba mesmo que role a tela. Se for
        // especificamente o erro de link expirado, o SnackBar ganha um
        // botão de ação para reenviar o e-mail na hora.
        setState(() => _errorMessage = result.message);
        final bool isExpiredLink =
            result.message?.toLowerCase().contains('link de confirmação') ?? false;

        if (result.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message!),
              duration: const Duration(seconds: 6),
              action: isExpiredLink
                  ? SnackBarAction(
                      label: 'Reenviar e-mail',
                      onPressed: () => _resendConfirmation(email),
                    )
                  : null,
            ),
          );
        }
        return;
      }

      // Sucesso, mas com uma mensagem para o usuário (ex: "verifique seu
      // e-mail") — não há sessão criada, então o AuthGate NÃO vai trocar
      // de tela sozinho. Se não avisássemos aqui, o usuário ficaria
      // olhando pro formulário sem entender por que nada aconteceu.
      if (result.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message!), duration: const Duration(seconds: 5)),
        );
      }

      // Sucesso completo (com sessão): não precisa fazer mais nada aqui
      // — o StreamBuilder do AuthGate detecta a nova sessão e troca de
      // tela sozinho.
    } catch (e) {
      // Rede de segurança final: mesmo que AuthService algum dia mude e
      // volte a deixar uma exceção escapar, ela é pega aqui — o loading
      // nunca fica preso esperando um retorno que não vem.
      if (mounted) {
        setState(() => _errorMessage = 'Erro inesperado: $e');
      }
    } finally {
      // `finally` garante que isto roda em QUALQUER caminho de saída da
      // função acima (sucesso, erro tratado, ou exceção não prevista) —
      // é o que efetivamente elimina o loading infinito.
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.darkest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _C.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isCreatingAccount ? 'Criar uma conta' : 'Que bom te ver de novo!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _C.textHeader, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDA373C).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFDA373C)),
                        ),
                        child: Text(_errorMessage!,
                            style: const TextStyle(color: Color(0xFFFCDCDC), fontSize: 13)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) {
                          return 'Informe seu e-mail.';
                        }
                        if (!_emailRegex.hasMatch(trimmed)) {
                          return 'Informe um e-mail válido (ex: nome@dominio.com).';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.length < _minPasswordLength) {
                          return 'Mínimo de $_minPasswordLength caracteres.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(backgroundColor: _C.blurple),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(_isCreatingAccount ? 'Criar Conta' : 'Entrar'),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _isSubmitting ? null : _toggleMode,
                      child: Text(
                        _isCreatingAccount
                            ? 'Já tem uma conta? Entrar'
                            : 'Precisa de uma conta? Criar Conta',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF00A8FC)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
