import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chitieu/core/money/money_formatter.dart';
import 'package:chitieu/core/money/money_settings_provider.dart';
import 'package:chitieu/api/tx/tx_provider.dart';

class TransactionsByFilterPage extends StatefulWidget {
  final String title;
  final String? walletId;
  final String? categoryId;
  final String? type; // 'thu' | 'chi'

  const TransactionsByFilterPage({
    super.key,
    required this.title,
    this.walletId,
    this.categoryId,
    this.type,
  });

  @override
  State<TransactionsByFilterPage> createState() => _TransactionsByFilterPageState();
}

class _TransactionsByFilterPageState extends State<TransactionsByFilterPage> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    context.read<TxProvider>().fetchByFilter(
          walletId: widget.walletId,
          categoryId: widget.categoryId,
          limit: 100,
          type: widget.type,
          year: _year,
          month: _month,
        );
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year -= 1;
      } else {
        _month -= 1;
      }
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year += 1;
      } else {
        _month += 1;
      }
    });
    _load();
  }

  Future<void> _pickMonth() async {
    // Dùng DatePicker để chọn ngày, sau đó lấy month/year của ngày được chọn
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_year, _month, 1),
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Chọn tháng',
    );
    if (picked != null) {
      setState(() {
        _year = picked.year;
        _month = picked.month;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final moneySettings = context.watch<MoneySettingsProvider>().settings;
    String fmt(num v) => MoneyFormatter(moneySettings).format(v);

    final txProv = context.watch<TxProvider>();
    final items = txProv.filtered;
    final loading = txProv.loadingFiltered;

    final monthLabel = DateFormat('MM/yyyy').format(DateTime(_year, _month, 1));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Tháng trước',
            onPressed: _prevMonth,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          InkWell(
            onTap: _pickMonth,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Center(
                child: Text(
                  monthLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tháng sau',
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: loading
          ? const LinearProgressIndicator(minHeight: 2)
          : (items.isEmpty)
              ? const Center(child: Text('Chưa có giao dịch nào'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) {
                    final tx = items[i];
                    final isOut = tx.type == 'chi';
                    final sign = isOut ? '-' : '+';
                    final color = isOut ? const Color(0xFFD64545) : const Color(0xFF1F9D4C);
                    final dateStr = DateFormat('dd/MM, HH:mm').format(tx.occurredAt);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(.15),
                        child: Icon(
                          isOut ? Icons.call_made_rounded : Icons.call_received_rounded,
                          color: color,
                        ),
                      ),
                      title: Text(
                        tx.categoryName ?? tx.walletName ?? (isOut ? 'Chi' : 'Thu'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text((tx.note?.isNotEmpty == true) ? tx.note! : dateStr),
                      trailing: Text(
                        '$sign${fmt(tx.amount)}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: color),
                      ),
                    );
                  },
                ),
    );
  }
}
