import 'package:chitieu/pages/budget_edit_page.dart';
import 'package:chitieu/utils/safe_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chitieu/api/category/category_provider.dart';
import 'package:chitieu/api/category/category_model.dart';

class CategoryManagePage extends StatefulWidget {
  const CategoryManagePage({super.key});

  @override
  State<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends State<CategoryManagePage> {
  Future<void> _refresh() async {
    await context.read<CategoryProvider>().refresh();
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BudgetEditPage()),
    );
    if (created == true) {
      await _refresh();
      if (mounted) {
        safeShowSnackBar(
          context,
          const SnackBar(content: Text('Đã tạo danh mục')),
        );
      }
    }
  }

  Future<void> _edit(Category c) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BudgetEditPage(category: c)),
    );
    if (changed == true) {
      await _refresh();
      if (mounted) {
        safeShowSnackBar(
          context,
          const SnackBar(content: Text('Đã cập nhật danh mục')),
        );
      }
    }
  }

  Future<void> _delete(Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận'),
        content: Text('Xoá danh mục "${c.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await context.read<CategoryProvider>().delete(id: c.id);
      await _refresh();
      if (mounted) {
        safeShowSnackBar(
          context,
          const SnackBar(content: Text('Đã xoá danh mục')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      safeShowSnackBar(
        context,
        SnackBar(content: Text('Xoá thất bại: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CategoryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý danh mục'),
        actions: [
          IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Thêm danh mục',
              onPressed: _create),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: provider.loading
            ? const Center(child: CircularProgressIndicator())
            : provider.items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 160),
                    Center(child: Text('Chưa có danh mục')),
                  ])
                : ListView.separated(
                    itemCount: provider.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = provider.items[i];
                      return ListTile(
                        leading: const Icon(Icons.category_outlined),
                        title: Text(c.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'Sửa',
                                onPressed: () => _edit(c)),
                            IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Xoá',
                                onPressed: () => _delete(c)),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
