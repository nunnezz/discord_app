import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

// =========================================================================
// RESULTADO DE UMA TENTATIVA DE AUTENTICAÇÃO
// =========================================================================
// Em vez de devolver só `String? erro`, usamos um resultado mais rico.
// Isso é o que resolve o loading infinito: existe um terceiro estado,
// além de "deu certo" e "deu erro", que é "deu certo, mas falta um
// passo" (confirmar o e-mail) — nesse caso NÃO há sessão criada, então
// o AuthGate nunca vai trocar de tela sozinho, e o chamador PRECISA
// saber disso para parar o spinner e avisar o usuário.
class AuthResult {
  final bool success;

  /// Mensagem para mostrar ao usuário. Pode vir preenchida mesmo em
  /// caso de sucesso (ex: "verifique seu e-mail"), ou em caso de erro
  /// (ex: "senha incorreta").
  final String? message;

  const AuthResult.success({this.message}) : success = true;
  const AuthResult.error(String errorMessage)
      : success = false,
        message = errorMessage;
}

// =========================================================================
// AUTH SERVICE
// Substitui o antigo mapa local de "contas cadastradas em memória" pelo
// Supabase Auth de verdade. O Supabase já cuida de: senha com hash e
// salt, checagem de e-mail duplicado, sessão persistida entre aberturas
// do app, etc.
// =========================================================================
class AuthService {
  /// Deriva um "nome de usuário" a partir da parte local do e-mail
  /// (tudo antes do "@"), só para preencher os metadados/`profiles`
  /// (coluna `username`, que tem a constraint `^[a-z0-9_.]{3,32}$` no
  /// schema.sql) — já que o formulário não pede mais um username
  /// separado, e sim o e-mail real.
  static String _usernameFromEmail(String email) {
    final localPart = email.split('@').first.toLowerCase();
    // Troca qualquer caractere fora de [a-z0-9_.] por "_", pra nunca
    // violar a constraint da tabela `profiles`.
    final sanitized = localPart.replaceAll(RegExp(r'[^a-z0-9_.]'), '_');
    return sanitized.isEmpty ? 'usuario' : sanitized;
  }

  /// Traduz qualquer erro (AuthException do Supabase, erro de rede, ou
  /// qualquer outra exceção) para uma mensagem amigável em português.
  /// Centralizado aqui para não duplicar essa lógica em signUp/signIn.
  static String _friendlyErrorMessage(Object error) {
    // Erros de rede / CORS / timeout — comuns no Flutter Web
    if (error is SocketException) {
      return 'Sem conexão com a internet. Verifique sua rede e tente novamente.';
    }
    if (error is HttpException) {
      return 'Erro de conexão com o servidor. Tente novamente em alguns instantes.';
    }
    if (error is TimeoutException) {
      return 'O servidor demorou demais para responder. Tente novamente.';
    }

    if (error is AuthException) {
      final msg = error.message.toLowerCase();

      // Rate limit: o Supabase bloqueia tentativas repetidas em pouco
      // tempo (ex: várias tentativas de cadastro/login seguidas).
      if (error.statusCode == '429' ||
          msg.contains('rate limit') ||
          msg.contains('too many requests') ||
          msg.contains('for security purposes')) {
        return 'Muitas tentativas em pouco tempo. Aguarde alguns segundos e tente novamente.';
      }
      if (msg.contains('already registered') || msg.contains('already exists')) {
        return 'Este e-mail já está cadastrado. Tente entrar em vez de criar conta.';
      }
      if (msg.contains('invalid login credentials')) {
        return 'E-mail ou senha incorretos.';
      }
      if (msg.contains('email not confirmed')) {
        return 'Confirme seu e-mail antes de entrar. Verifique sua caixa de entrada (e o spam).';
      }
      // Link de confirmação/recuperação expirado ou já usado. O Supabase
      // chama isso de "OTP" internamente mesmo sendo um link por e-mail
      // (o link contém um token de uso único com validade curta).
      if (msg.contains('otp') && (msg.contains('expired') || msg.contains('invalid'))) {
        return 'Este link de confirmação expirou ou já foi usado. '
            'Peça um novo e-mail de confirmação e clique nele assim que chegar.';
      }
      if (msg.contains('email link is invalid or has expired')) {
        return 'Este link de confirmação expirou ou já foi usado. '
            'Peça um novo e-mail de confirmação e clique nele assim que chegar.';
      }
      // Fallback: mostra a mensagem original do Supabase, é melhor que nada.
      return error.message;
    }

    // Erros de rede (sem internet, timeout, DNS, etc.) não são
    // AuthException — caem aqui. `error.runtimeType` ajuda a
    // diagnosticar em debug sem expor detalhes técnicos ao usuário.
    final errorStr = error.toString();
    if (errorStr.contains('decode') || errorStr.contains('CORS') || errorStr.contains('cross-origin')) {
      return 'Erro de configuração do servidor. Verifique se as variáveis de ambiente (SUPABASE_URL e SUPABASE_ANON_KEY) estão configuradas no deploy.';
    }
    return 'Não foi possível se conectar ao servidor. Verifique sua internet e tente novamente.';
  }

  /// Cria a conta. Usa o e-mail REAL digitado pelo usuário — necessário
  /// para o fluxo de confirmação de e-mail / recuperação de senha do
  /// Supabase funcionar de verdade. O nome de usuário salvo em
  /// `profiles` (via os metadados abaixo, lidos pelo trigger
  /// `handle_new_user`) continua sendo gerado automaticamente a partir
  /// do e-mail.
  ///
  /// IMPORTANTE: se o seu projeto Supabase tiver "Confirm email"
  /// habilitado (Authentication → Providers → Email), a conta é criada
  /// mas SEM sessão ativa — o usuário precisa clicar no link recebido
  /// por e-mail antes de conseguir entrar. Tratamos esse caso
  /// explicitamente abaixo (`response.session == null`) em vez de supor
  /// que "usuário não-nulo" sempre significa "login concluído" — era
  /// exatamente essa suposição errada que deixava o spinner girando
  /// para sempre, esperando uma troca de tela que nunca vinha.
  static Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final derivedUsername = _usernameFromEmail(email);

      final response = await supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'username': derivedUsername,
          'display_name': derivedUsername,
        },
      );

      if (response.user == null) {
        return const AuthResult.error(
          'Não foi possível criar a conta. Tente novamente.',
        );
      }

      if (response.session == null) {
        // Conta criada, mas precisa confirmar o e-mail antes de logar.
        // Isso NÃO é um erro — por isso `AuthResult.success`, só que
        // com uma mensagem para o usuário, e sem sessão nenhuma.
        return const AuthResult.success(
          message:
              'Conta criada! Verifique seu e-mail para confirmar antes de entrar.',
        );
      }

      // Sucesso completo: já existe sessão, o AuthGate troca de tela sozinho.
      return const AuthResult.success();
    } catch (e) {
      // Cobre AuthException E qualquer outra coisa (erro de rede, etc.)
      // — nenhuma exceção escapa sem virar um AuthResult.error, então
      // quem chamou este método SEMPRE recebe uma resposta e pode
      // desligar o loading.
      return AuthResult.error(_friendlyErrorMessage(e));
    }
  }

  /// Retorna sucesso/erro com mensagem amigável. O Supabase não
  /// diferencia "conta não existe" de "senha incorreta" por segurança,
  /// então usamos uma mensagem genérica, igual o próprio Discord faz.
  static Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.session == null) {
        return const AuthResult.error('E-mail ou senha incorretos.');
      }
      return const AuthResult.success();
    } catch (e) {
      return AuthResult.error(_friendlyErrorMessage(e));
    }
  }

  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  /// Reenvia o e-mail de confirmação de cadastro. Use isso quando o
  /// usuário receber o erro de "link expirado" — em vez de travar o
  /// fluxo, ele pode pedir um link novo direto pelo app.
  /// Retorna `null` em caso de sucesso, ou uma mensagem de erro.
  static Future<String?> resendConfirmationEmail(String email) async {
    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
      );
      return null;
    } catch (e) {
      return _friendlyErrorMessage(e);
    }
  }

  /// Stream que emite sempre que o estado de login muda (login, logout,
  /// sessão restaurada ao abrir o app). É isso que o AuthGate escuta.
  static Stream<AuthState> get onAuthStateChange =>
      supabase.auth.onAuthStateChange;
}
