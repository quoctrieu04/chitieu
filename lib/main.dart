import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

// --- Auth ---
import 'package:chitieu/auth/auth_provider.dart';
import 'package:chitieu/auth/auth_service.dart';

// --- Settings ---
import 'pages/setting/settings_provider.dart';

// --- Pages ---
import 'pages/budgets_page.dart';
import 'pages/accounts_page.dart';
import 'pages/analytics_page.dart';
import 'pages/setting/setting_page.dart';
import 'pages/setting/money_settings_page.dart';
import 'pages/note_page.dart';

// --- i18n ---
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:chitieu/l10n/app_localizations.dart';

// --- Wallet ---
import 'api/wallet/wallet_service.dart';
import 'api/wallet/wallet_provider.dart';

// --- Money ---
import 'core/money/money_settings_provider.dart';
import 'core/money/money_settings_service.dart';

// --- Budgets ---
import 'core/budget/budget_service.dart';
import 'core/budget/budgets_provider.dart';

// --- Category ---
import 'api/category/category_service.dart';
import 'api/category/category_provider.dart';

// --- Transactions ---
import 'api/tx/tx_service.dart';
import 'api/tx/tx_provider.dart';
import 'pages/transactions_page.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // IP/LAN backend của bạn
  const base = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://172.20.10.3:8000', // đổi IP 192.168.1.67:8000
  );
  final apiBase = '$base/api';

  // Auth service (dùng chung cho cả app)
  final authApi = AuthService(base);

  // Duy nhất 1 Dio + interceptor
  final dio = Dio(BaseOptions(baseUrl: apiBase));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await authApi.getToken();

        // GẮN / GỠ Authorization tuỳ theo token
        if (token != null && token.isNotEmpty && token != 'null') {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          options.headers.remove('Authorization'); // ⬅️ quan trọng
        }

        options.headers['Accept'] = 'application/json';
        options.headers['Content-Type'] = 'application/json';

        final auth = (options.headers['Authorization'] as String?) ?? '';
        final preview = auth.length >= 16
            ? auth.substring(0, 16)
            : (auth.isEmpty ? '(none)' : auth);
        // ignore: avoid_print
        print('[REQ] ${options.method} ${options.uri} auth=$preview...');

        handler.next(options);
      },
    ),
  );

  // Money settings local
  final moneyProv = MoneySettingsProvider(MoneySettingsService());
  await moneyProv.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<MoneySettingsProvider>.value(value: moneyProv),

        // ===== Auth =====
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authApi)..bootstrap(),
        ),

        // ===== Wallet =====
        ChangeNotifierProxyProvider<AuthProvider, WalletProvider>(
          create: (_) => WalletProvider(
            service: WalletService(baseUrl: apiBase, token: ''),
          ),
          update: (_, auth, prev) {
            final p = prev ??
                WalletProvider(
                    service: WalletService(baseUrl: apiBase, token: ''));

            final token = auth.token ?? '';
            p.updateToken(token);

            if (token.isEmpty) {
              // Chưa login / đã logout -> xoá state
              try {
                p.clear();
              } catch (_) {}
              return p;
            }

            // Có token -> fetch lần đầu
            if (p.items.isEmpty && !p.loading) {
              // ignore: discarded_futures
              p.fetch();
            }
            return p;
          },
        ),

        // ===== Category =====
        ChangeNotifierProxyProvider<AuthProvider, CategoryProvider>(
          create: (_) => CategoryProvider(
            service: CategoryService(baseUrl: apiBase, token: ''),
          ),
          update: (_, auth, prev) {
            final p = prev ??
                CategoryProvider(
                  service: CategoryService(baseUrl: apiBase, token: ''),
                );

            final token = auth.token ?? '';
            if (token.isEmpty) {
              try {
                p.clear();
              } catch (_) {}
              p.service.token = '';
              return p;
            }

            if (p.service.token != token) {
              p.service.token = token;
              // ignore: discarded_futures
              p.refresh();
            } else if (p.items.isEmpty && !p.loading) {
              // ignore: discarded_futures
              p.refresh();
            }
            return p;
          },
        ),

        // ===== Budgets (gắn theo Auth để clear khi chưa login) =====
        ChangeNotifierProxyProvider<AuthProvider, BudgetsProvider>(
          create: (_) => BudgetsProvider(BudgetService(dio, authApi)),
          update: (_, auth, prev) {
            final p = prev ?? BudgetsProvider(BudgetService(dio, authApi));
            final token = auth.token ?? '';

            if (token.isEmpty) {
              try {
                p.clear();
              } catch (_) {}
            }
            return p;
          },
        ),

        // ===== Transactions =====
        ChangeNotifierProvider(
          create: (ctx) => TxProvider(
            api: TxService(dio), // DIO chung (có Bearer qua interceptor)
            wallets: ctx.read<WalletProvider>(), // cập nhật số dư ví
            budgets: ctx.read<
                BudgetsProvider>(), // refresh ngân sách sau khi tạo giao dịch
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // i18n
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('vi'), Locale('en')],
      locale: settings.locale,

      // theme
      themeMode: settings.themeMode,
      theme: ThemeData(
        useMaterial3: false,
        colorScheme: ColorScheme.fromSeed(seedColor: settings.seed),
        scaffoldBackgroundColor: const Color(0xFFFAF3E6),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.seed,
          brightness: Brightness.dark,
        ),
      ),

      // text scale
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: TextScaler.linear(settings.textScale),
        ),
        child: child!,
      ),

      title: 'Chi Tiêu',
      home: const HomeScaffold(),
      routes: {
        '/settings/money': (_) => const MoneySettingsPage(),
         '/transactions':   (_) => const TransactionsPage(),
      },
    );
  }
}

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});
  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    BudgetsPage(),
    AccountsPage(),
    AnalyticsPage(),
    SettingsPage(),
  ];

  void _onTabSelected(int index) => setState(() => _currentIndex = index);

  void _onFabPressed() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    const Color selectedColor = Colors.amber;
    const Color unselectedColor = Colors.black54;

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabPressed,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(Icons.assignment),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: _NavItem(
                          icon: Icons.wallet_rounded,
                          label: t.tabBudgets,
                          selected: _currentIndex == 0,
                          selectedColor: selectedColor,
                          unselectedColor: unselectedColor,
                          onTap: () => _onTabSelected(0),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.account_balance_rounded,
                          label: t.tabAccounts,
                          selected: _currentIndex == 1,
                          selectedColor: selectedColor,
                          unselectedColor: unselectedColor,
                          onTap: () => _onTabSelected(1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 64),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: _NavItem(
                          icon: Icons.insights_rounded,
                          label: t.tabAnalytics,
                          selected: _currentIndex == 2,
                          selectedColor: selectedColor,
                          unselectedColor: unselectedColor,
                          onTap: () => _onTabSelected(2),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.settings_rounded,
                          label: t.tabSettings,
                          selected: _currentIndex == 3,
                          selectedColor: selectedColor,
                          unselectedColor: unselectedColor,
                          onTap: () => _onTabSelected(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
