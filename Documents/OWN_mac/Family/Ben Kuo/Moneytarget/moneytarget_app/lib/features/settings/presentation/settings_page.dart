import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/category_settings.dart';
import '../../../data/models/currency_settings.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/mock_money_repository.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.onUpdateGoal,
    required this.onUpdateCategories,
    required this.currencySettings,
    required this.onUpdateCurrency,
    required this.onExportData,
    required this.onImportData,
  });

  final MockMoneyRepository repository;
  final Future<void> Function(Goal goal) onUpdateGoal;
  final Future<void> Function(CategorySettings settings) onUpdateCategories;
  final CurrencySettings currencySettings;
  final Future<void> Function(CurrencySettings settings) onUpdateCurrency;
  final Future<Map<String, dynamic>> Function() onExportData;
  final Future<void> Function(Map<String, dynamic> data) onImportData;

  @override
  Widget build(BuildContext context) {
    final goal = repository.goal;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(title: '目標設定'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  label: '目標金額',
                  value: currencySettings.format(goal.targetAmount),
                ),
                _InfoRow(
                  label: '開始日期',
                  value: DateFormat.yMMMd().format(goal.startDate),
                ),
                _InfoRow(
                  label: '結束日期',
                  value: DateFormat.yMMMd().format(goal.endDate),
                ),
                _InfoRow(
                  label: '總週數',
                  value: '${goal.totalWeeks} 週',
                ),
                _InfoRow(
                  label: '總月數',
                  value: '${goal.totalMonths} 月',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _showGoalEditor(context, goal),
                  icon: const Icon(Icons.edit),
                  label: const Text('編輯目標'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle(title: '通知與提醒'),
        Card(
          child: SwitchListTile(
            title: const Text('每月存款提醒'),
            subtitle: Text('每月平均：${currencySettings.format(goal.requiredMonthlyAmount)}'),
            value: true,
            onChanged: (value) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(value ? '已開啟提醒' : '已關閉提醒'),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle(title: '幣別設定'),
        CurrencySettingsCard(
          settings: currencySettings,
          onChanged: onUpdateCurrency,
        ),
        const SizedBox(height: 24),
        _SectionTitle(title: '快速統計'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow(
                  label: '收入總額',
                  value: currencySettings.format(repository.totalIncome),
                ),
                _InfoRow(
                  label: '存款總額',
                  value: currencySettings.format(repository.totalSaving),
                ),
                _InfoRow(
                  label: '支出總額',
                  value: currencySettings.format(repository.totalExpense),
                ),
                _InfoRow(
                  label: '類別數量',
                  value:
                      '${repository.expenseTotalsByCategory().keys.length} 類',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle(title: '類別管理'),
        CategoryManagerSection(
          initialSettings: repository.categorySettings,
          onChanged: onUpdateCategories,
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: '關於'),
        const AboutCard(),
        const SizedBox(height: 24),
        _SectionTitle(title: '資料管理'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: const Text('匯入資料'),
                subtitle: const Text('貼上 JSON 資料以覆蓋目前內容'),
                onTap: () => _showImportDialog(context),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('匯出資料'),
                subtitle: const Text('匯出 JSON 資料，可複製或分享'),
                onTap: () => _handleExport(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleExport(BuildContext context) async {
    final data = await onExportData();
    final encoder = const JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(data);
    if (!context.mounted) return;

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/moneytarget_export_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);
      await Share.shareXFiles([XFile(file.path)], text: 'MoneyTarget 匯出資料');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯出失敗：$error')),
      );
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final jsonString = utf8.decode(bytes);
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      await onImportData(decoded);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資料已匯入')), 
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯入失敗：$error')),
      );
    }
  }

  Future<void> _showGoalEditor(BuildContext context, Goal goal) async {
    final updatedGoal = await showModalBottomSheet<Goal>(
      context: context,
      isScrollControlled: true,
      builder: (context) => GoalEditSheet(goal: goal),
    );
    if (!context.mounted) return;
    if (updatedGoal != null) {
      await onUpdateGoal(updatedGoal);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目標已更新')),
      );
    }
  }
}

class CategoryManagerSection extends StatefulWidget {
  const CategoryManagerSection({
    super.key,
    required this.initialSettings,
    required this.onChanged,
  });

  final CategorySettings initialSettings;
  final Future<void> Function(CategorySettings settings) onChanged;

  @override
  State<CategoryManagerSection> createState() => _CategoryManagerSectionState();
}

class _CategoryManagerSectionState extends State<CategoryManagerSection> {
  late CategorySettings _settings;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  @override
  void didUpdateWidget(covariant CategoryManagerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSettings != widget.initialSettings && !_isSaving) {
      _settings = widget.initialSettings;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CategoryEditor(
              title: '收入來源',
              values: _settings.incomeSources,
              color: Colors.blue,
              onAdd: (value) => _updateCategories(TransactionType.income, value),
              onRemove: (value) => _removeValue(TransactionType.income, value),
            ),
            const SizedBox(height: 16),
            _CategoryEditor(
              title: '存款來源',
              values: _settings.savingSources,
              color: Theme.of(context).colorScheme.primary,
              onAdd: (value) => _updateCategories(TransactionType.saving, value),
              onRemove: (value) => _removeValue(TransactionType.saving, value),
            ),
            const SizedBox(height: 16),
            _CategoryEditor(
              title: '支出類別',
              values: _settings.expenseCategories,
              color: Theme.of(context).colorScheme.error,
              onAdd: (value) => _updateCategories(TransactionType.expense, value),
              onRemove: (value) => _removeValue(TransactionType.expense, value),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateCategories(TransactionType type, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    setState(() => _isSaving = true);
    final updated = _settings.addValue(type, trimmed);
    await widget.onChanged(updated);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _isSaving = false;
    });
  }

  Future<void> _removeValue(TransactionType type, String value) async {
    final list = switch (type) {
      TransactionType.income => _settings.incomeSources,
      TransactionType.saving => _settings.savingSources,
      TransactionType.expense => _settings.expenseCategories,
    };

    if (list.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需保留一個選項')),
      );
      return;
    }

    setState(() => _isSaving = true);

    CategorySettings updated;
    switch (type) {
      case TransactionType.income:
        updated = _settings.copyWith(
          incomeSources: list.where((item) => item != value).toList(),
        );
        break;
      case TransactionType.saving:
        updated = _settings.copyWith(
          savingSources: list.where((item) => item != value).toList(),
        );
        break;
      case TransactionType.expense:
        updated = _settings.copyWith(
          expenseCategories: list.where((item) => item != value).toList(),
        );
        break;
    }

    await widget.onChanged(updated);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _isSaving = false;
    });
  }
}

class CurrencySettingsCard extends StatefulWidget {
  const CurrencySettingsCard({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final CurrencySettings settings;
  final Future<void> Function(CurrencySettings settings) onChanged;

  @override
  State<CurrencySettingsCard> createState() => _CurrencySettingsCardState();
}

class _CurrencySettingsCardState extends State<CurrencySettingsCard> {
  late CurrencySettings _settings;
  late TextEditingController _rateController;
  late FocusNode _rateFocusNode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _rateController = TextEditingController(
      text: widget.settings.audToTwdRate.toStringAsFixed(2),
    );
    _rateFocusNode = FocusNode();
    _rateFocusNode.addListener(() {
      if (!_rateFocusNode.hasFocus) {
        _updateRate();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CurrencySettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings && !_saving) {
      _settings = widget.settings;
      _rateController.text = widget.settings.audToTwdRate.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    _rateFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<Currency>(
              segments: const [
                ButtonSegment(
                  value: Currency.twd,
                  label: Text('新台幣 (NT\$)'),
                ),
                ButtonSegment(
                  value: Currency.aud,
                  label: Text('澳幣 (AU\$)'),
                ),
              ],
              selected: {_settings.selectedCurrency},
              onSelectionChanged: (selection) =>
                  _updateCurrency(selection.first),
            ),
            if (_settings.selectedCurrency == Currency.aud) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _rateController,
                focusNode: _rateFocusNode,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '匯率 (1 AU\$ = ? NT\$)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check),
                    tooltip: '儲存匯率',
                    onPressed: _updateRate,
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _updateRate(),
                onEditingComplete: _updateRate,
                onTapOutside: (_) => _updateRate(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _updateCurrency(Currency currency) async {
    if (currency == _settings.selectedCurrency) return;
    setState(() => _saving = true);
    final updated = _settings.copyWith(selectedCurrency: currency);
    await widget.onChanged(updated);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _saving = false;
    });
  }

  Future<void> _updateRate() async {
    final parsed = double.tryParse(_rateController.text.trim());
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入正確匯率')),
      );
      _rateController.text = _settings.audToTwdRate.toStringAsFixed(2);
      return;
    }
    setState(() => _saving = true);
    final updated = _settings.copyWith(audToTwdRate: parsed);
    await widget.onChanged(updated);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _saving = false;
      _rateController.text = _settings.audToTwdRate.toStringAsFixed(2);
    });
    FocusScope.of(context).unfocus();
  }
}

class _CategoryEditor extends StatelessWidget {
  const _CategoryEditor({
    required this.title,
    required this.values,
    required this.color,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<String> values;
  final Color color;
  final Future<void> Function(String value) onAdd;
  final Future<void> Function(String value) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新增$title',
              onPressed: () async {
                final value = await _promptForValue(context, title);
                if (value != null) {
                  await onAdd(value);
                }
              },
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (value) => InputChip(
                  label: Text(value),
                  backgroundColor: color.withValues(alpha: 0.12),
                  onDeleted: () => onRemove(value),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Future<String?> _promptForValue(BuildContext context, String title) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('新增$title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pop(value);
              }
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }
}

class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _InfoRow(label: '版本號', value: '1.0.0'),
            _InfoRow(label: '著作權所有', value: 'Fusion Next Inc.'),
            _InfoRow(label: '聯絡我們', value: '+886-932-215629'),
            _InfoRow(label: 'Email', value: 'contact@fusionnextinc.com'),
          ],
        ),
      ),
    );
  }
}

class GoalEditSheet extends StatefulWidget {
  const GoalEditSheet({super.key, required this.goal});

  final Goal goal;

  @override
  State<GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<GoalEditSheet> {
  late final TextEditingController _amountController;
  late DateTime _startDate;
  late DateTime _endDate;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _startDate = widget.goal.startDate;
    _endDate = widget.goal.endDate;
    _amountController = TextEditingController(
      text: widget.goal.targetAmount.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: padding.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '編輯目標',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: '目標金額',
                prefixText: 'NT\$',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '請輸入金額';
                }
                final parsed = double.tryParse(value.replaceAll(',', ''));
                if (parsed == null || parsed <= 0) {
                  return '金額需為正數';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _DateField(
              label: '開始日期',
              date: _startDate,
              onPressed: () => _pickDate(isStart: true),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: '結束日期',
              date: _endDate,
              onPressed: () => _pickDate(isStart: false),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('儲存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_startDate.isAfter(_endDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _startDate = _endDate;
        }
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text.replaceAll(',', ''));
    final updatedGoal = Goal(
      targetAmount: amount,
      startDate: _startDate,
      endDate: _endDate,
    );
    Navigator.of(context).pop(updatedGoal);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onPressed,
  });

  final String label;
  final DateTime date;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(DateFormat.yMMMd().format(date)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

