import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;

import 'package:chitieu/l10n/app_localizations.dart';
import 'package:chitieu/api/category/category_provider.dart';
import 'package:chitieu/api/category/category_model.dart';
import 'package:chitieu/core/budget/budgets_provider.dart';
import 'package:chitieu/core/budget/budget_model.dart';

// ✅ lấy token
import 'package:chitieu/auth/auth_provider.dart';
import 'package:chitieu/auth/auth_service.dart';

// ================= CONFIG =================
// ignore: constant_identifier_names
const String _API_BASE_URL = "http://192.168.1.67:8000";

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  DateTime _ym = DateTime(DateTime.now().year, DateTime.now().month);

  // --- Dữ liệu AI ---
  bool _loadingAI = false;
  double? _predictedExpense;
  List<dynamic> _alerts = [];
  String? _aiError;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final b = context.read<BudgetsProvider>();
      final c = context.read<CategoryProvider>();
      await Future.wait([
        b.loadForMonth(year: _ym.year, month: _ym.month),
        if (!c.loading && c.items.isEmpty) c.refresh(),
      ]);
      _fetchPrediction();
    });
  }

  // ================= GỌI API DỰ BÁO (kèm cảnh báo) =================
  Future<void> _fetchPrediction() async {
    try {
      _safeSetState(() {
        _loadingAI = true;
        _aiError = null;
      });

      final token = await _getAccessTokenFromYourAuth();

      final uri = Uri.parse("$_API_BASE_URL/api/predict").replace(
        queryParameters: {
          'year': _ym.year.toString(),
          'month': _ym.month.toString(),
        },
      );

      final res = await http
          .get(
            uri,
            headers: {
              "Authorization": "Bearer $token",
              "Accept": "application/json",
            },
          )
          .timeout(const Duration(seconds: 12));

      debugPrint("[AI] GET $uri -> ${res.statusCode}");
      debugPrint("[AI] body: ${res.body}");

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final num? v =
            (data['prediction'] as num?) ?? (data['predicted_expense'] as num?);

        // ====== LỌC ALERTS: chỉ status còn hiệu lực + đúng tháng + khử trùng theo code ======
        final rawAlerts = data['alerts'];
        final List<Map<String, dynamic>> alerts =
            (rawAlerts is List) ? rawAlerts.cast<Map<String, dynamic>>() : [];

        // 1) chỉ lấy status còn hiệu lực
        List<Map<String, dynamic>> filtered = alerts.where((a) {
          final st = (a['status'] ?? 'new').toString().toLowerCase();
          final active = st == 'new' || st == 'open';

          // 2) đúng tháng đang xem (_ym)
          final createdAt = (a['created_at'] ?? '').toString();
          DateTime? dt;
          try {
            dt = DateTime.parse(createdAt).toLocal();
          } catch (_) {}
          final inMonth = dt != null && dt.year == _ym.year && dt.month == _ym.month;

          return active && inMonth;
        }).toList();

        // 3) sắp xếp mới → cũ
        filtered.sort((a, b) {
          DateTime pa, pb;
          try {
            pa = DateTime.parse(a['created_at']).toLocal();
          } catch (_) {
            pa = DateTime.fromMillisecondsSinceEpoch(0);
          }
          try {
            pb = DateTime.parse(b['created_at']).toLocal();
          } catch (_) {
            pb = DateTime.fromMillisecondsSinceEpoch(0);
          }
          return pb.compareTo(pa);
        });

        // 4) khử trùng theo code: giữ bản MỚI NHẤT mỗi loại
        final seenCodes = <String>{};
        filtered = filtered.where((a) {
          final code = (a['code'] ?? '').toString();
          if (seenCodes.contains(code)) return false;
          seenCodes.add(code);
          return true;
        }).toList();
        // ====== END FILTER ======

        _safeSetState(() {
          _predictedExpense = v?.toDouble();
          _alerts = filtered;
          _loadingAI = false;
        });
        return;
      }

      if (res.statusCode == 401) {
        _safeSetState(() {
          _aiError = "Bạn chưa đăng nhập hoặc phiên đã hết hạn (401).";
          _loadingAI = false;
        });
        return;
      }

      try {
        final err = jsonDecode(res.body);
        final msg = err is Map && err['message'] is String
            ? err['message'] as String
            : "Lỗi API: ${res.statusCode}";
        _safeSetState(() {
          _aiError = msg;
          _loadingAI = false;
        });
      } catch (_) {
        _safeSetState(() {
          _aiError = "Lỗi API: ${res.statusCode}";
          _loadingAI = false;
        });
      }
    } catch (e) {
      _safeSetState(() {
        _aiError = "Không kết nối được tới server: $e";
        _loadingAI = false;
      });
    }
  }

  // ✅ Trả về token đăng nhập hiện tại
  Future<String> _getAccessTokenFromYourAuth() async {
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated && auth.token != null && auth.token!.isNotEmpty) {
      return auth.token!;
    }
    final t = await AuthService.readToken();
    if (t != null && t.isNotEmpty) return t;
    throw "Chưa đăng nhập";
  }

  // ==================================================
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final budgetsProv = context.watch<BudgetsProvider>();
    final catsProv = context.watch<CategoryProvider>();

    final items = budgetsProv.items;
    final categories = {for (final c in catsProv.items) c.id: c};

    // Đã phân bổ (tổng ngân sách theo danh mục)
    final totalAssigned = budgetsProv.totalAssigned;

    // Tổng đã tiêu (cộng từ từng budget item)
    num totalSpent = 0;
    for (final it in items) {
      try {
        final s = (it as dynamic).spent; // đổi nếu field khác
        if (s is num) totalSpent += s;
      } catch (_) {}
    }

    // ✅ Chưa phân bổ: lấy trực tiếp từ provider
    final num unallocated = budgetsProv.unallocated;

    final total =
        items.map((e) => e.amount).where((v) => v > 0).fold<num>(0, (a, b) => a + b);
    final nf = NumberFormat.decimalPattern(locale);
    final monthLabel = DateFormat.yMMMM(locale).format(_ym);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              t.analyticsTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(monthLabel,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: t.selectMonth,
            onPressed: () async {
              final picked = await _pickMonth(context, initial: _ym);
              if (picked != null) {
                setState(() => _ym = picked);
                await budgetsProv.loadForMonth(
                    year: _ym.year, month: _ym.month);
                _fetchPrediction();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            budgetsProv.loadForMonth(year: _ym.year, month: _ym.month),
            if (!catsProv.loading) catsProv.refresh(),
          ]);
          await _fetchPrediction();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------- Thẻ Dự báo & Cảnh báo ----------
            _Card(
              title: "Dự báo & Cảnh báo",
              child: _buildPredictionCard(nf),
            ),
            const SizedBox(height: 16),

            // ---------- Biểu đồ phân bổ ----------
            _Card(
              title: t.analyticsBudgetSplit,
              child: total <= 0
                  ? _Empty(text: t.noDataThisMonth)
                  : _BudgetPieChart(items: items, categories: categories),
            ),
            const SizedBox(height: 16),

            // ---------- Danh sách top danh mục ----------
            _Card(
              title: t.topCategories,
              child: total <= 0
                  ? _Empty(text: t.noDataThisMonth)
                  : _TopCategoriesList(
                      items: items,
                      categories: categories,
                      number: nf,
                    ),
            ),
            const SizedBox(height: 16),

            // ---------- Tổng quan / Tổng kết ----------
            _Card(
              title: t.summary,
              child: _SummaryBox(
                totalAssigned: totalAssigned,
                totalSpent: totalSpent,
                unallocated: unallocated, // ✅ truyền trực tiếp
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================== CARD DỰ BÁO ==================
  Widget _buildPredictionCard(NumberFormat nf) {
    if (_loadingAI) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_aiError != null) {
      final notLoggedIn = _aiError!.contains('Chưa đăng nhập') ||
          _aiError!.contains('hết hạn') ||
          _aiError!.contains('401');
      if (notLoggedIn) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Bạn chưa đăng nhập hoặc phiên đã hết hạn.",
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/login');
              },
              icon: const Icon(Icons.login),
              label: const Text("Đăng nhập"),
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_aiError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _fetchPrediction,
            icon: const Icon(Icons.refresh),
            label: const Text("Thử lại"),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_predictedExpense != null)
          Text(
            "Chi tiêu dự báo tháng sau: đ ${nf.format(_predictedExpense!.round())}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          )
        else
          const Text("Chưa có dữ liệu dự báo.",
              style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 8),

        if (_alerts.isEmpty)
          const Text("Không có cảnh báo.", style: TextStyle(color: Colors.black54))
        else
          Column(
            children: _alerts.map((a) {
              final msg = (a['message'] ?? '').toString();

              final rawLevel = (a['level'] ?? 'info').toString().toLowerCase();
              final normalized = switch (rawLevel) {
                'critical' || 'danger' => 'danger',
                'warning' || 'warn' => 'warn',
                _ => 'info',
              };
              final (color, icon) = _levelToUi(normalized);

              final createdAt = a['created_at']?.toString();
              String? timeStr;
              if (createdAt != null && createdAt.isNotEmpty) {
                try {
                  final dt = DateTime.parse(createdAt).toLocal();
                  final loc = Localizations.localeOf(context).toLanguageTag();
                  timeStr = DateFormat.yMd(loc).add_Hm().format(dt);
                } catch (_) {}
              }

              return Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.isEmpty ? 'Có cảnh báo mới.' : msg,
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                          if (timeStr != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              timeStr,
                              style: TextStyle(
                                color: color.withOpacity(.9),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  (Color, IconData) _levelToUi(String level) {
    switch (level) {
      case 'danger':
        return (Colors.red, Icons.error_outline);
      case 'warn':
        return (Colors.orange, Icons.warning_amber_rounded);
      case 'info':
      default:
        return (Colors.blue, Icons.info_outline);
    }
  }

  Future<DateTime?> _pickMonth(BuildContext context,
      {required DateTime initial}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1),
      lastDate: DateTime(2035, 12),
      helpText: AppLocalizations.of(context)!.selectMonth,
    );
    if (picked == null) return null;
    return DateTime(picked.year, picked.month);
  }
}

/* ------------------ Widget phụ ------------------ */

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        elevation: .5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(text)));
}

/// Biểu đồ tròn phân bổ danh mục
class _BudgetPieChart extends StatelessWidget {
  const _BudgetPieChart({required this.items, required this.categories});
  final List<BudgetItem> items;
  final Map<int, Category> categories;

  @override
  Widget build(BuildContext context) {
    final data = items.where((e) => e.amount > 0).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final total = data.fold<num>(0, (a, b) => a + b.amount);

    final sections = data.map((e) {
      final percent = total == 0 ? 0 : (e.amount / total) * 100;
      return PieChartSectionData(
        value: e.amount.toDouble(),
        title: '${percent.toStringAsFixed(0)}%',
        radius: 70,
        titleStyle: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
                sections: sections, sectionsSpace: 2, centerSpaceRadius: 40),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: data.take(8).map((e) {
            final name = categories[e.categoryId]?.name ?? '#${e.categoryId}';
            final pct = total == 0 ? 0 : (e.amount / total) * 100;
            return Chip(
              label: Text('$name (${pct.toStringAsFixed(0)}%)'),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Danh sách top danh mục
class _TopCategoriesList extends StatelessWidget {
  const _TopCategoriesList(
      {required this.items, required this.categories, required this.number});
  final List<BudgetItem> items;
  final Map<int, Category> categories;
  final NumberFormat number;

  @override
  Widget build(BuildContext context) {
    final data = items.where((e) => e.amount > 0).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return Column(
      children: data
          .map((it) => ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: Colors.green.withOpacity(.08),
                  child: Text(
                    (categories[it.categoryId]?.name ?? '#')[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(
                  categories[it.categoryId]?.name ??
                      'Danh mục ${it.categoryId}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Text(
                  'đ ${number.format(it.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ))
          .toList(),
    );
  }
}

/// ==================== TỔNG KẾT: HÀNG NGANG (CÓ CỘNG CHƯA PHÂN BỔ) ====================
class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.totalAssigned,
    required this.totalSpent,
    required this.unallocated,
  });

  final num totalAssigned;
  final num totalSpent;
  final num unallocated;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final nf = NumberFormat.decimalPattern(locale);

    final remainingAssigned = totalAssigned - totalSpent;
    final overallRemaining = remainingAssigned + unallocated; // 👈 cộng chưa phân bổ
    final remainingColor = overallRemaining >= 0 ? Colors.green : Colors.red;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: _SummaryTile(
            label: "Đã phân bổ",
            value: 'đ ${nf.format(totalAssigned)}',
            icon: Icons.pie_chart_rounded,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            label: "Đã tiêu",
            value: 'đ ${nf.format(totalSpent)}',
            icon: Icons.payments_rounded,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            label: overallRemaining >= 0 ? "Còn dư" : "Vượt",
            value: 'đ ${nf.format(overallRemaining.abs())}',
            subtitle: unallocated > 0
                ? 'Bao gồm chưa phân bổ: đ ${nf.format(unallocated)}'
                : null,
            icon: overallRemaining >= 0
                ? Icons.savings_rounded
                : Icons.report_gmailerrorred_rounded,
            color: remainingColor,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
}
