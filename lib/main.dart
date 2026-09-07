// =========================================================================
// CORD - Um clone visual e funcional do Discord, feito em Flutter (Web).
// Autor: Claude (atuando como Dev Sênior Flutter / UX-UI)
//
// Como rodar:
//   flutter create cord_app
//   (substitua o conteúdo de lib/main.dart por este arquivo)
//   flutter run -d chrome
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const CordApp());
}

// =========================================================================
// PALETA DE CORES (fiel ao tema escuro padrão do Discord)
// =========================================================================
class CordColors {
  static const Color darkest = Color(0xFF1E1F22); // Barra de servidores
  static const Color darker = Color(0xFF2B2D31); // Barra de canais
  static const Color chatBg = Color(0xFF313338); // Área principal de chat
  static const Color membersBg = Color(0xFF2B2D31); // Barra de membros
  static const Color inputBg = Color(0xFF383A40); // Campo de digitação
  static const Color hoverChannel = Color(0xFF35373C);
  static const Color activeChannel = Color(0xFF404249);
  static const Color blurple = Color(0xFF5865F2); // Cor icônica do Discord
  static const Color green = Color(0xFF23A55A); // Status online
  static const Color textNormal = Color(0xFFDBDEE1);
  static const Color textMuted = Color(0xFF949BA4);
  static const Color textHeader = Color(0xFFF2F3F5);
  static const Color divider = Color(0xFF3F4147);
}

// =========================================================================
// APP RAIZ
// =========================================================================
class CordApp extends StatelessWidget {
  const CordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cord',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: CordColors.chatBg,
        fontFamily: 'Roboto',
        useMaterial3: true,
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            const Color(0xFF1A1B1E).withOpacity(0.6),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// =========================================================================
// AUTENTICAÇÃO
// =========================================================================

/// Controla qual tela é exibida: Login/Criar Conta ou o app principal.
/// Em um app real, isso seria substituído por um listener de estado de
/// autenticação (ex: Firebase Auth, backend próprio, etc).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

/// Registro interno de uma conta cadastrada: guardamos a senha e também
/// o nome de usuário exatamente como foi digitado no cadastro (com a
/// capitalização original), já que a checagem de duplicidade é feita de
/// forma normalizada (ver `_normalizeUsername`).
class _AccountRecord {
  final String password;
  final String displayUsername;
  const _AccountRecord({required this.password, required this.displayUsername});
}

class _AuthGateState extends State<AuthGate> {
  // "Banco de dados" local e simples: mapeia nome de usuário -> conta.
  // Em um app real isso viria de um backend (Firebase, API própria, etc.),
  // mas aqui simulamos o cadastro guardando as contas em memória.
  //
  // A CHAVE do mapa é o nome de usuário NORMALIZADO (sem espaços nas
  // pontas e em minúsculas). Isso garante que "Ana", "ana" e " ana "
  // sejam tratados como o MESMO usuário, evitando duplicidade — a causa
  // mais comum de "duplicados" escaparem de uma checagem ingênua com
  // comparação sensível a maiúsculas/minúsculas ou espaços.
  final Map<String, _AccountRecord> _registeredAccounts = {};

  // Nome do usuário autenticado. Nulo enquanto não há login.
  String? _loggedInUsername;

  /// Normaliza um nome de usuário para fins de comparação/armazenamento
  /// como chave: remove espaços nas extremidades e ignora maiúsculas.
  String _normalizeUsername(String username) => username.trim().toLowerCase();

  /// Tenta autenticar com uma conta já existente.
  /// Retorna `null` em caso de sucesso, ou uma mensagem de erro.
  String? _tryLogin(String username, String password) {
    final key = _normalizeUsername(username);
    final account = _registeredAccounts[key];

    if (account == null) {
      return 'Essa conta não existe. Verifique o usuário ou crie uma conta.';
    }
    if (account.password != password) {
      return 'Senha incorreta. Tente novamente.';
    }

    setState(() => _loggedInUsername = account.displayUsername);
    return null;
  }

  /// Cadastra uma nova conta e já autentica o usuário.
  /// Retorna `null` em caso de sucesso, ou uma mensagem de erro.
  ///
  /// REGRA DE DUPLICIDADE: antes de salvar, verifica se já existe uma
  /// conta com o mesmo nome de usuário normalizado. Se existir, o
  /// cadastro é bloqueado e uma mensagem de erro clara é retornada.
  String? _tryRegister(String username, String password) {
    final key = _normalizeUsername(username);

    if (_registeredAccounts.containsKey(key)) {
      return 'Este nome de usuário já está em uso, escolha outro.';
    }

    _registeredAccounts[key] = _AccountRecord(
      password: password,
      displayUsername: username.trim(),
    );
    setState(() => _loggedInUsername = username.trim());
    return null;
  }

  void _handleLogout() {
    setState(() => _loggedInUsername = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedInUsername == null) {
      return AuthScreen(
        onLogin: _tryLogin,
        onRegister: _tryRegister,
      );
    }
    return CordHomePage(
      loggedInUsername: _loggedInUsername!,
      onLogout: _handleLogout,
    );
  }
}

/// Assinatura das funções de autenticação: recebem usuário/senha e
/// retornam `null` em caso de sucesso, ou uma mensagem de erro a exibir.
typedef AuthAttempt = String? Function(String username, String password);

/// Tela única que alterna entre "Entrar" e "Criar Conta".
class AuthScreen extends StatefulWidget {
  final AuthAttempt onLogin;
  final AuthAttempt onRegister;

  const AuthScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // true = modo "Criar Conta", false = modo "Entrar"
  bool _isCreatingAccount = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  // Mensagem de erro geral (ex: senha curta, conta inexistente, senha
  // incorreta, usuário já cadastrado), exibida em destaque no card.
  String? _errorMessage;

  static const int _minPasswordLength = 6;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isCreatingAccount = !_isCreatingAccount;
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final isFormValid = _formKey.currentState?.validate() ?? false;
    if (!isFormValid) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Regra de validação explícita: senha com no mínimo 6 dígitos.
    // Aplicada tanto no cadastro quanto no login, antes mesmo de consultar
    // a lista de contas.
    if (password.length < _minPasswordLength) {
      setState(() {
        _errorMessage =
            'A senha deve ter no mínimo $_minPasswordLength caracteres.';
      });
      return;
    }

    setState(() => _isSubmitting = true);

    // Simula uma chamada de rede (autenticação em backend/Firebase/etc).
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Consulta a "base de contas" mantida pelo AuthGate: cria uma nova
    // conta ou valida usuário + senha de uma conta já existente.
    final String? error = _isCreatingAccount
        ? widget.onRegister(username, password)
        : widget.onLogin(username, password);

    if (error != null) {
      // Falhou: reabilita o formulário e mostra o motivo exato do erro
      // (conta inexistente, senha incorreta ou usuário já cadastrado).
      setState(() {
        _isSubmitting = false;
        _errorMessage = error;
      });
      return;
    }

    // Sucesso: o AuthGate já trocou de tela para o CordHomePage,
    // não há mais nada a fazer aqui.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CordColors.darkest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: CordColors.chatBg,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo / marca do app
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: CordColors.blurple,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.forum_rounded,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Cord',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isCreatingAccount
                          ? 'Criar uma conta'
                          : 'Que bom te ver de novo!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CordColors.textHeader,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isCreatingAccount
                          ? 'Preencha os campos abaixo para começar.'
                          : 'Estamos muito felizes em te ver novamente!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CordColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Mensagem de erro em destaque
                    if (_errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDA373C).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFDA373C),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_rounded,
                                color: Color(0xFFDA373C), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFFCDCDC),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Campo: Nome de usuário
                    _AuthLabel(text: 'NOME DE USUÁRIO'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _usernameController,
                      style: const TextStyle(color: CordColors.textNormal),
                      decoration: _authInputDecoration(),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Informe um nome de usuário.';
                        }
                        if (value.trim().length < 3) {
                          return 'O nome de usuário deve ter no mínimo 3 caracteres.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Campo: Senha
                    _AuthLabel(
                      text: _isCreatingAccount
                          ? 'SENHA  (mín. $_minPasswordLength dígitos)'
                          : 'SENHA',
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: CordColors.textNormal),
                      decoration: _authInputDecoration(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: CordColors.textMuted,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Informe sua senha.';
                        }
                        if (value.length < _minPasswordLength) {
                          return 'A senha deve ter no mínimo $_minPasswordLength caracteres.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),

                    // Botão de ação principal (Entrar / Criar Conta)
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CordColors.blurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          disabledBackgroundColor:
                              CordColors.blurple.withOpacity(0.6),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Text(
                                _isCreatingAccount ? 'Criar Conta' : 'Entrar',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Alternância entre "Entrar" e "Criar Conta"
                    GestureDetector(
                      onTap: _isSubmitting ? null : _toggleMode,
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 13.5, color: CordColors.textMuted),
                          children: [
                            TextSpan(
                              text: _isCreatingAccount
                                  ? 'Já tem uma conta? '
                                  : 'Precisa de uma conta? ',
                            ),
                            TextSpan(
                              text: _isCreatingAccount
                                  ? 'Entrar'
                                  : 'Criar Conta',
                              style: const TextStyle(
                                color: Color(0xFF00A8FC),
                                fontWeight: FontWeight.w600,
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
          ),
        ),
      ),
    );
  }

  InputDecoration _authInputDecoration({Widget? suffixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: CordColors.darkest,
      suffixIcon: suffixIcon,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: CordColors.blurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFFDA373C), width: 1),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFF8B8B), fontSize: 12),
    );
  }
}

class _AuthLabel extends StatelessWidget {
  final String text;
  const _AuthLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: CordColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

// =========================================================================
// MODELOS DE DADOS
// =========================================================================

class ServerModel {
  final String name;
  final String initials;
  final Color color;
  const ServerModel(
      {required this.name, required this.initials, required this.color});
}

enum ChannelType { text, voice }

class ChannelModel {
  final String name;
  final ChannelType type;
  const ChannelModel({required this.name, required this.type});
}

class CategoryModel {
  final String title;
  final List<ChannelModel> channels;
  const CategoryModel({required this.title, required this.channels});
}

class MemberModel {
  final String name;
  final Color statusColor;
  final String avatarLetter;
  final Color avatarColor;
  const MemberModel({
    required this.name,
    required this.statusColor,
    required this.avatarLetter,
    required this.avatarColor,
  });
}

class MessageModel {
  final String author;
  final Color avatarColor;
  final String time;
  final String content;
  final bool isNew;
  const MessageModel({
    required this.author,
    required this.avatarColor,
    required this.time,
    required this.content,
    this.isNew = false,
  });
}

// =========================================================================
// PÁGINA PRINCIPAL - Mantém todo o estado do app (servidor, canal, chat)
// =========================================================================
class CordHomePage extends StatefulWidget {
  final String loggedInUsername;
  final VoidCallback onLogout;

  const CordHomePage({
    super.key,
    required this.loggedInUsername,
    required this.onLogout,
  });

  @override
  State<CordHomePage> createState() => _CordHomePageState();
}

class _CordHomePageState extends State<CordHomePage> {
  // -------------------- DADOS MOCKADOS --------------------
  final List<ServerModel> servers = const [
    ServerModel(name: 'Flutter Devs', initials: 'FD', color: Color(0xFF5865F2)),
    ServerModel(name: 'Gamers United', initials: 'GU', color: Color(0xFFEB459E)),
    ServerModel(name: 'Design Hub', initials: 'DH', color: Color(0xFF23A55A)),
    ServerModel(name: 'Música & Cia', initials: 'MC', color: Color(0xFFF0B232)),
  ];

  final List<CategoryModel> categories = const [
    CategoryModel(title: 'CANAIS DE TEXTO', channels: [
      ChannelModel(name: 'geral', type: ChannelType.text),
      ChannelModel(name: 'anúncios', type: ChannelType.text),
      ChannelModel(name: 'dúvidas-flutter', type: ChannelType.text),
      ChannelModel(name: 'off-topic', type: ChannelType.text),
    ]),
    CategoryModel(title: 'CANAIS DE VOZ', channels: [
      ChannelModel(name: 'Sala Geral', type: ChannelType.voice),
      ChannelModel(name: 'Estudando Juntos', type: ChannelType.voice),
      ChannelModel(name: 'AFK', type: ChannelType.voice),
    ]),
  ];

  final List<MemberModel> onlineMembers = const [
    MemberModel(
        name: 'Ana Souza',
        statusColor: CordColors.green,
        avatarLetter: 'A',
        avatarColor: Color(0xFFF0B232)),
    MemberModel(
        name: 'Bruno Lima',
        statusColor: CordColors.green,
        avatarLetter: 'B',
        avatarColor: Color(0xFF5865F2)),
    MemberModel(
        name: 'Carla Dias',
        statusColor: CordColors.green,
        avatarLetter: 'C',
        avatarColor: Color(0xFFEB459E)),
    MemberModel(
        name: 'você',
        statusColor: CordColors.green,
        avatarLetter: 'V',
        avatarColor: Color(0xFF23A55A)),
  ];

  final List<MemberModel> botMembers = const [
    MemberModel(
        name: 'MEE6',
        statusColor: CordColors.green,
        avatarLetter: 'M',
        avatarColor: Color(0xFF949BA4)),
  ];

  // -------------------- ESTADO MUTÁVEL --------------------
  int selectedServerIndex = 0;
  String selectedChannel = 'geral';
  bool showMembersPanel = true;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late List<MessageModel> messages;

  @override
  void initState() {
    super.initState();
    messages = [
      const MessageModel(
        author: 'Ana Souza',
        avatarColor: Color(0xFFF0B232),
        time: 'Hoje às 09:12',
        content: 'Bom dia, pessoal! Alguém já viu o novo release do Flutter? 🚀',
      ),
      const MessageModel(
        author: 'Bruno Lima',
        avatarColor: Color(0xFF5865F2),
        time: 'Hoje às 09:14',
        content: 'Vi sim! O hot reload ficou ainda mais rápido, muito bom pra produtividade.',
      ),
      const MessageModel(
        author: 'Carla Dias',
        avatarColor: Color(0xFFEB459E),
        time: 'Hoje às 09:20',
        content:
            'Alguém pode revisar meu PR? Fiz uma tela nova seguindo o design system que combinamos.',
      ),
      const MessageModel(
        author: 'MEE6',
        avatarColor: Color(0xFF949BA4),
        time: 'Hoje às 09:22',
        content: '📢 Novo membro entrou no servidor: bem-vindo(a)!',
      ),
    ];
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // -------------------- FUNÇÕES --------------------

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add(MessageModel(
        author: 'você',
        avatarColor: CordColors.green,
        time: _currentTimeLabel(),
        content: text,
        isNew: true,
      ));
      _messageController.clear();
    });

    // Rola a lista de mensagens até o final após o rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _currentTimeLabel() {
    final now = TimeOfDay.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return 'Hoje às $hour:$minute';
  }

  /// Roteia o toque no canal: canais de TEXTO apenas trocam a área de chat;
  /// canais de VOZ abrem a tela de chamada em tela cheia.
  void _handleChannelTap(ChannelModel channel) {
    if (channel.type == ChannelType.voice) {
      _openVoiceCall(channel.name);
    } else {
      setState(() => selectedChannel = channel.name);
    }
  }

  void _openVoiceCall(String channelName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VoiceCallScreen(
          channelName: channelName,
          serverName: servers[selectedServerIndex].name,
          participants: onlineMembers,
          currentUsername: widget.loggedInUsername,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _selectServer(int index) {
    setState(() {
      selectedServerIndex = index;
      // Ao trocar de servidor, resetamos para o canal padrão "geral".
      selectedChannel = 'geral';
    });
  }

  // -------------------- BUILD --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _ServerSidebar(
            servers: servers,
            selectedIndex: selectedServerIndex,
            onServerTap: _selectServer,
          ),
          _ChannelSidebar(
            serverName: servers[selectedServerIndex].name,
            categories: categories,
            selectedChannel: selectedChannel,
            onChannelTap: _handleChannelTap,
            username: widget.loggedInUsername,
            onLogout: widget.onLogout,
          ),
          Expanded(
            child: _ChatArea(
              channelName: selectedChannel,
              messages: messages,
              controller: _messageController,
              scrollController: _scrollController,
              onSend: _sendMessage,
              onToggleMembers: () {
                setState(() => showMembersPanel = !showMembersPanel);
              },
              membersPanelOpen: showMembersPanel,
            ),
          ),
          if (showMembersPanel)
            _MembersSidebar(
              onlineMembers: onlineMembers,
              botMembers: botMembers,
            ),
        ],
      ),
    );
  }
}

// =========================================================================
// 1. BARRA LATERAL DE SERVIDORES (Esquerda)
// =========================================================================
class _ServerSidebar extends StatelessWidget {
  final List<ServerModel> servers;
  final int selectedIndex;
  final ValueChanged<int> onServerTap;

  const _ServerSidebar({
    required this.servers,
    required this.selectedIndex,
    required this.onServerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      color: CordColors.darkest,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Ícone "Home" do app (Cord)
          _ServerIcon(
            isSelected: false,
            isHome: true,
            child: const Icon(Icons.forum_rounded, color: Colors.white, size: 26),
            onTap: () {},
          ),
          const SizedBox(height: 8),
          Container(
            height: 2,
            width: 32,
            color: CordColors.divider,
            margin: const EdgeInsets.symmetric(vertical: 4),
          ),
          const SizedBox(height: 4),
          // Lista de servidores
          Expanded(
            child: ListView.builder(
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                final isSelected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ServerIcon(
                    isSelected: isSelected,
                    color: server.color,
                    tooltip: server.name,
                    child: Text(
                      server.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    onTap: () => onServerTap(index),
                  ),
                );
              },
            ),
          ),
          // Botão de destaque para adicionar novo servidor
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ServerIcon(
              isSelected: false,
              isAddButton: true,
              tooltip: 'Adicionar servidor',
              child: const Icon(Icons.add_rounded,
                  color: CordColors.green, size: 26),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}

/// Ícone circular de servidor com animação de hover/seleção,
/// incluindo o indicador de "pílula" branca à esquerda (estilo Discord).
class _ServerIcon extends StatefulWidget {
  final Widget child;
  final bool isSelected;
  final bool isHome;
  final bool isAddButton;
  final Color? color;
  final String? tooltip;
  final VoidCallback onTap;

  const _ServerIcon({
    required this.child,
    required this.isSelected,
    required this.onTap,
    this.isHome = false,
    this.isAddButton = false,
    this.color,
    this.tooltip,
  });

  @override
  State<_ServerIcon> createState() => _ServerIconState();
}

class _ServerIconState extends State<_ServerIcon> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bool rounded = widget.isSelected || _hovering;
    final Color bgColor = widget.isAddButton
        ? CordColors.darker
        : widget.isHome
            ? CordColors.blurple
            : (widget.color ?? CordColors.blurple);

    Widget iconWidget = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Indicador de seleção/hover (barrinha branca à esquerda)
            Positioned(
              left: -12,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 4,
                height: widget.isSelected ? 36 : (_hovering ? 20 : 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(rounded ? 16 : 24),
              ),
              alignment: Alignment.center,
              child: widget.child,
            ),
          ],
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        preferBelow: false,
        verticalOffset: 28,
        textStyle: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: iconWidget,
      );
    }
    return iconWidget;
  }
}

// =========================================================================
// 2. BARRA LATERAL DE CANAIS (Meio-Esquerda)
// =========================================================================
class _ChannelSidebar extends StatelessWidget {
  final String serverName;
  final List<CategoryModel> categories;
  final String selectedChannel;
  final ValueChanged<ChannelModel> onChannelTap;
  final String username;
  final VoidCallback onLogout;

  const _ChannelSidebar({
    required this.serverName,
    required this.categories,
    required this.selectedChannel,
    required this.onChannelTap,
    required this.username,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: CordColors.darker,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho com nome do servidor + menu suspenso simulado
          _ServerHeader(serverName: serverName),
          const SizedBox(height: 8),
          // Lista de categorias e canais
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final category in categories)
                  _CategorySection(
                    category: category,
                    selectedChannel: selectedChannel,
                    onChannelTap: onChannelTap,
                  ),
              ],
            ),
          ),
          // Rodapé com "perfil do usuário" (estilo Discord)
          _UserFooter(username: username, onLogout: onLogout),
        ],
      ),
    );
  }
}

class _ServerHeader extends StatefulWidget {
  final String serverName;
  const _ServerHeader({required this.serverName});

  @override
  State<_ServerHeader> createState() => _ServerHeaderState();
}

class _ServerHeaderState extends State<_ServerHeader> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _menuOpen = !_menuOpen),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CordColors.divider, width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.serverName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CordColors.textHeader,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                _menuOpen ? Icons.close_rounded : Icons.keyboard_arrow_down_rounded,
                color: CordColors.textNormal,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySection extends StatefulWidget {
  final CategoryModel category;
  final String selectedChannel;
  final ValueChanged<ChannelModel> onChannelTap;

  const _CategorySection({
    required this.category,
    required this.selectedChannel,
    required this.onChannelTap,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 16,
                  color: CordColors.textMuted,
                ),
                const SizedBox(width: 2),
                Text(
                  widget.category.title,
                  style: const TextStyle(
                    color: CordColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final channel in widget.category.channels)
            _ChannelTile(
              channel: channel,
              isSelected: channel.name == widget.selectedChannel,
              onTap: () => widget.onChannelTap(channel),
            ),
      ],
    );
  }
}

class _ChannelTile extends StatefulWidget {
  final ChannelModel channel;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bool highlight = widget.isSelected || _hovering;
    final Color bg = widget.isSelected
        ? CordColors.activeChannel
        : (_hovering ? CordColors.hoverChannel : Colors.transparent);
    final Color fg = widget.isSelected ? Colors.white : CordColors.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  widget.channel.type == ChannelType.text
                      ? Icons.tag_rounded
                      : Icons.volume_up_rounded,
                  size: 20,
                  color: highlight ? CordColors.textNormal : CordColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight:
                          widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                // Dica visual de que o canal de voz é clicável (abre a chamada).
                if (widget.channel.type == ChannelType.voice && _hovering)
                  const Icon(Icons.call_rounded,
                      size: 16, color: CordColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rodapé fixo estilo Discord mostrando o "usuário logado".
class _UserFooter extends StatelessWidget {
  final String username;
  final VoidCallback onLogout;

  const _UserFooter({required this.username, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final String initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Container(
      height: 52,
      color: const Color(0xFF232428),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: CordColors.blurple,
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: CordColors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF232428), width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const Text('Online',
                    style: TextStyle(color: CordColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.mic_rounded, size: 18, color: CordColors.textNormal),
            onPressed: () {},
            tooltip: 'Mutar microfone',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded,
                size: 18, color: CordColors.textNormal),
            onPressed: onLogout,
            tooltip: 'Sair da conta',
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// 3. ÁREA PRINCIPAL DE CHAT (Centro)
// =========================================================================
class _ChatArea extends StatelessWidget {
  final String channelName;
  final List<MessageModel> messages;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onToggleMembers;
  final bool membersPanelOpen;

  const _ChatArea({
    required this.channelName,
    required this.messages,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onToggleMembers,
    required this.membersPanelOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CordColors.chatBg,
      child: Column(
        children: [
          _ChatTopBar(
            channelName: channelName,
            onToggleMembers: onToggleMembers,
            membersPanelOpen: membersPanelOpen,
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return _MessageBubble(message: messages[index]);
              },
            ),
          ),
          _MessageInputBar(controller: controller, onSend: onSend, channelName: channelName),
        ],
      ),
    );
  }
}

class _ChatTopBar extends StatelessWidget {
  final String channelName;
  final VoidCallback onToggleMembers;
  final bool membersPanelOpen;

  const _ChatTopBar({
    required this.channelName,
    required this.onToggleMembers,
    required this.membersPanelOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CordColors.chatBg,
        border: const Border(bottom: BorderSide(color: CordColors.divider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.tag_rounded, color: CordColors.textMuted, size: 22),
          const SizedBox(width: 6),
          Text(
            channelName,
            style: const TextStyle(
              color: CordColors.textHeader,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: CordColors.divider),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Bem-vindo(a) ao canal! Fique à vontade para conversar.',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: CordColors.textMuted, fontSize: 14),
            ),
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search_rounded, color: CordColors.textMuted),
            onPressed: () {},
          ),
          IconButton(
            tooltip: membersPanelOpen ? 'Ocultar membros' : 'Mostrar membros',
            icon: Icon(
              Icons.group_rounded,
              color: membersPanelOpen ? Colors.white : CordColors.textMuted,
            ),
            onPressed: onToggleMembers,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: _hovering ? Colors.black.withOpacity(0.06) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: widget.message.avatarColor,
              child: Text(
                widget.message.author.isNotEmpty
                    ? widget.message.author[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.message.author,
                        style: const TextStyle(
                          color: CordColors.textHeader,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.message.time,
                        style: const TextStyle(
                          color: CordColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.message.content,
                    style: const TextStyle(
                      color: CordColors.textNormal,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra de digitação fixa, funcional: envia com clique no botão ou Enter.
class _MessageInputBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final String channelName;

  const _MessageInputBar({
    required this.controller,
    required this.onSend,
    required this.channelName,
  });

  @override
  State<_MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<_MessageInputBar> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onSend();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Container(
        decoration: BoxDecoration(
          color: CordColors.inputBg,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Botão de anexar arquivo (+)
            IconButton(
              tooltip: 'Anexar arquivo',
              icon: const Icon(Icons.add_circle_rounded,
                  color: CordColors.textMuted, size: 26),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Simulação: anexo de arquivo.'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            // Campo de texto
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: _handleKey,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  style: const TextStyle(color: CordColors.textNormal, fontSize: 15),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    hintText: 'Conversar em #${widget.channelName}',
                    hintStyle: const TextStyle(color: CordColors.textMuted),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  onSubmitted: (_) => widget.onSend(),
                  textInputAction: TextInputAction.send,
                ),
              ),
            ),
            // Ícones extras (emoji / gif) para fidelidade visual
            IconButton(
              tooltip: 'Emoji',
              icon: const Icon(Icons.emoji_emotions_rounded,
                  color: CordColors.textMuted, size: 22),
              onPressed: () {},
            ),
            // Botão de envio funcional
            IconButton(
              tooltip: 'Enviar mensagem',
              icon: const Icon(Icons.send_rounded, color: CordColors.blurple, size: 22),
              onPressed: widget.onSend,
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 4. BARRA DE MEMBROS ONLINE (Direita - Colapsável)
// =========================================================================
class _MembersSidebar extends StatelessWidget {
  final List<MemberModel> onlineMembers;
  final List<MemberModel> botMembers;

  const _MembersSidebar({
    required this.onlineMembers,
    required this.botMembers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: CordColors.membersBg,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        children: [
          _MemberGroup(title: 'ONLINE — ${onlineMembers.length}', members: onlineMembers),
          const SizedBox(height: 16),
          _MemberGroup(title: 'BOTS — ${botMembers.length}', members: botMembers),
        ],
      ),
    );
  }
}

class _MemberGroup extends StatelessWidget {
  final String title;
  final List<MemberModel> members;

  const _MemberGroup({required this.title, required this.members});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: CordColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        for (final member in members) _MemberTile(member: member),
      ],
    );
  }
}

class _MemberTile extends StatefulWidget {
  final MemberModel member;
  const _MemberTile({required this.member});

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _hovering ? CordColors.hoverChannel : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: widget.member.avatarColor,
                  child: Text(
                    widget.member.avatarLetter,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: widget.member.statusColor,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: CordColors.membersBg, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.member.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CordColors.textMuted,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 5. TELA DE CHAMADA DE VOZ / VÍDEO (simulada)
// =========================================================================
//
// Aberta ao clicar em um canal de voz. Contém: grade de participantes,
// controles de microfone e câmera (com estado visual de ligado/desligado)
// e o botão vermelho de "Desconectar", que retorna para a tela de chat.
class VoiceCallScreen extends StatefulWidget {
  final String channelName;
  final String serverName;
  final List<MemberModel> participants;
  final String currentUsername;

  const VoiceCallScreen({
    super.key,
    required this.channelName,
    required this.serverName,
    required this.participants,
    required this.currentUsername,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  bool _micMuted = false;
  bool _cameraOn = false;
  bool _deafened = false;

  void _toggleMic() => setState(() => _micMuted = !_micMuted);
  void _toggleCamera() => setState(() => _cameraOn = !_cameraOn);
  void _toggleDeafen() => setState(() => _deafened = !_deafened);

  void _disconnect() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Monta a lista de "participantes" da chamada: o usuário atual entra
    // automaticamente, junto dos membros online simulados do servidor.
    final List<_CallParticipant> callParticipants = [
      _CallParticipant(
        name: '${widget.currentUsername} (você)',
        color: CordColors.green,
        cameraOn: _cameraOn,
        speaking: !_micMuted,
      ),
      for (final member in widget.participants.where((m) => m.name != 'você'))
        _CallParticipant(
          name: member.name,
          color: member.avatarColor,
          cameraOn: false,
          speaking: false,
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF1A1B1E),
      body: SafeArea(
        child: Column(
          children: [
            _CallTopBar(
              serverName: widget.serverName,
              channelName: widget.channelName,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Grade responsiva: mais colunas quando há mais espaço.
                    final int columns = constraints.maxWidth > 900
                        ? 3
                        : constraints.maxWidth > 560
                            ? 2
                            : 1;
                    return GridView.builder(
                      itemCount: callParticipants.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 16 / 10,
                      ),
                      itemBuilder: (context, index) {
                        return _CallParticipantTile(
                            participant: callParticipants[index]);
                      },
                    );
                  },
                ),
              ),
            ),
            _CallControlBar(
              micMuted: _micMuted,
              cameraOn: _cameraOn,
              deafened: _deafened,
              onToggleMic: _toggleMic,
              onToggleCamera: _toggleCamera,
              onToggleDeafen: _toggleDeafen,
              onDisconnect: _disconnect,
            ),
          ],
        ),
      ),
    );
  }
}

/// Modelo interno simples para representar cada card de participante na chamada.
class _CallParticipant {
  final String name;
  final Color color;
  final bool cameraOn;
  final bool speaking;

  const _CallParticipant({
    required this.name,
    required this.color,
    required this.cameraOn,
    required this.speaking,
  });
}

/// Barra superior da chamada com nome do canal e duração simulada.
class _CallTopBar extends StatelessWidget {
  final String serverName;
  final String channelName;

  const _CallTopBar({required this.serverName, required this.channelName});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CordColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.volume_up_rounded, color: CordColors.textMuted, size: 20),
          const SizedBox(width: 8),
          Text(
            channelName,
            style: const TextStyle(
              color: CordColors.textHeader,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '· $serverName',
            style: const TextStyle(color: CordColors.textMuted, fontSize: 13),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: CordColors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CordColors.green, width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: CordColors.green, size: 8),
                SizedBox(width: 6),
                Text(
                  'Conectado',
                  style: TextStyle(
                    color: CordColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card individual de cada participante dentro da grade de chamada.
/// Mostra avatar (quando câmera desligada) ou um placeholder de vídeo
/// (quando câmera ligada), além do nome e um indicador de "falando".
class _CallParticipantTile extends StatelessWidget {
  final _CallParticipant participant;
  const _CallParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF232428),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: participant.speaking ? CordColors.green : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Fundo: simula um "vídeo" com câmera ligada ou avatar quando desligada.
          Positioned.fill(
            child: participant.cameraOn
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          participant.color.withOpacity(0.55),
                          const Color(0xFF1A1B1E),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.videocam_rounded,
                        color: Colors.white.withOpacity(0.85), size: 42),
                  )
                : Container(
                    color: const Color(0xFF232428),
                    alignment: Alignment.center,
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: participant.color,
                      child: Text(
                        participant.name.isNotEmpty
                            ? participant.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
          ),
          // Rótulo com o nome do participante, no canto inferior esquerdo.
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (participant.speaking)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.mic_rounded,
                          color: CordColors.green, size: 14),
                    ),
                  Text(
                    participant.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra inferior fixa com os controles da chamada: mutar, câmera,
/// ensurdecer (deafen) e o botão vermelho de desconectar.
class _CallControlBar extends StatelessWidget {
  final bool micMuted;
  final bool cameraOn;
  final bool deafened;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleDeafen;
  final VoidCallback onDisconnect;

  const _CallControlBar({
    required this.micMuted,
    required this.cameraOn,
    required this.deafened,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleDeafen,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CordColors.divider, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CallActionButton(
            icon: micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            isActive: micMuted,
            tooltip: micMuted ? 'Ativar microfone' : 'Mutar microfone',
            onTap: onToggleMic,
          ),
          const SizedBox(width: 16),
          _CallActionButton(
            icon: cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            isActive: !cameraOn,
            tooltip: cameraOn ? 'Desligar câmera' : 'Ligar câmera',
            onTap: onToggleCamera,
          ),
          const SizedBox(width: 16),
          _CallActionButton(
            icon: deafened ? Icons.headset_off_rounded : Icons.headset_mic_rounded,
            isActive: deafened,
            tooltip: deafened ? 'Reativar áudio' : 'Ensurdecer',
            onTap: onToggleDeafen,
          ),
          const SizedBox(width: 24),
          // Botão vermelho de desconectar — sempre em destaque.
          _CallActionButton(
            icon: Icons.call_end_rounded,
            isActive: false,
            isDisconnect: true,
            tooltip: 'Desconectar',
            onTap: onDisconnect,
          ),
        ],
      ),
    );
  }
}

/// Botão circular reutilizável para os controles da chamada, com estado
/// "ativo" (destacado em branco, indicando mudo/câmera desligada/etc.)
/// e um modo especial vermelho para o botão de desconectar.
class _CallActionButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final bool isDisconnect;
  final String tooltip;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.isActive,
    required this.tooltip,
    required this.onTap,
    this.isDisconnect = false,
  });

  @override
  State<_CallActionButton> createState() => _CallActionButtonState();
}

class _CallActionButtonState extends State<_CallActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final Color bgColor = widget.isDisconnect
        ? const Color(0xFFDA373C)
        : widget.isActive
            ? Colors.white
            : const Color(0xFF2B2D31);
    final Color iconColor = widget.isDisconnect
        ? Colors.white
        : widget.isActive
            ? Colors.black
            : Colors.white;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.isDisconnect ? 64 : 52,
            height: 52,
            transform: Matrix4.identity()..scale(_hovering ? 1.06 : 1.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.isDisconnect ? 26 : 16),
              boxShadow: _hovering
                  ? [
                      BoxShadow(
                        color: bgColor.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }
}