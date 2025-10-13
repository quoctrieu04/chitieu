import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:chitieu/api/tx/tx_provider.dart';
import 'package:chitieu/core/money/money_formatter.dart';
import 'package:chitieu/core/money/money_settings_provider.dart';

class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final txProv = context.watch<TxProvider>();
    final settings = context.watch<MoneySettingsProvider>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text("Tất cả giao dịch")),
      body: RefreshIndicator(
        onRefresh: () => context.read<TxProvider>().fetchRecent(limit: 50),
        child: txProv.loadingRecent
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: txProv.recent.length,
                itemBuilder: (ctx, i) {
                  final tx = txProv.recent[i];
                  final isOut = tx.type == 'chi';
                  final sign = isOut ? '-' : '+';
                  final color =
                      isOut ? const Color(0xFFD64545) : const Color(0xFF1F9D4C);
                  final dateStr =
                      DateFormat('dd/MM/yyyy HH:mm').format(tx.occurredAt);

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(.15),
                      child: Icon(
                        isOut
                            ? Icons.call_made_rounded
                            : Icons.call_received_rounded,
                        color: color,
                      ),
                    ),
                    title: Text(
                      tx.categoryName ??
                          tx.walletName ??
                          (isOut ? 'Chi' : 'Thu'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                        (tx.note?.isNotEmpty == true) ? tx.note! : dateStr),
                    trailing: Text(
                      '$sign${MoneyFormatter(settings).format(tx.amount)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: color),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
