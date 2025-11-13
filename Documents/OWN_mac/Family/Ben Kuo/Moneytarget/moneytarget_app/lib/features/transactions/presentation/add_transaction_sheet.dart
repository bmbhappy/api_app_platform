import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../data/models/currency_settings.dart';
import '../../../data/models/money_entry.dart';
import '../../../data/models/transaction_type.dart';

class AddTransactionSheet extends StatefulWidget {
  const AddTransactionSheet({
    super.key,
    required this.initialType,
    this.initialEntry,
    required this.incomeSources,
    required this.savingSources,
    required this.expenseCategories,
    this.onCreateCategory,
    required this.currencySettings,
  });

  final TransactionType initialType;
  final MoneyEntry? initialEntry;
  final List<String> incomeSources;
  final List<String> savingSources;
  final List<String> expenseCategories;
  final Future<void> Function(TransactionType type, String value)? onCreateCategory;
  final CurrencySettings currencySettings;

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  static const String _customValueKey = '__custom__';

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _noteController = TextEditingController();

  late TransactionType _type;
  DateTime _selectedDate = DateTime.now();
  late List<String> _incomeOptions;
  late List<String> _savingOptions;
  late List<String> _expenseOptions;

  @override
  void initState() {
    super.initState();
    _type = widget.initialEntry?.type ?? widget.initialType;
    _selectedDate = widget.initialEntry?.date ?? DateTime.now();
    _incomeOptions = List<String>.from(widget.incomeSources);
    _savingOptions = List<String>.from(widget.savingSources);
    _expenseOptions = List<String>.from(widget.expenseCategories);
    if (widget.initialEntry != null) {
      final amount = widget.initialEntry!.amount;
      final displayAmount =
           widget.currencySettings.toDisplay(amount);
       final decimals =
           widget.currencySettings.selectedCurrency == Currency.twd ? 0 : 2;
      _amountController.text = displayAmount.toStringAsFixed(decimals);
      _sourceController.text = widget.initialEntry!.source ?? '';
      _categoryController.text = widget.initialEntry!.category ?? '';
      _noteController.text = widget.initialEntry!.note ?? '';
    }
  }

  @override
  void didUpdateWidget(covariant AddTransactionSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.incomeSources, widget.incomeSources)) {
      _incomeOptions = List<String>.from(widget.incomeSources);
    }
    if (!listEquals(oldWidget.savingSources, widget.savingSources)) {
      _savingOptions = List<String>.from(widget.savingSources);
    }
    if (!listEquals(oldWidget.expenseCategories, widget.expenseCategories)) {
      _expenseOptions = List<String>.from(widget.expenseCategories);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final dateFormat = DateFormat.yMMMd('zh_TW');

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: bottomInset + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.initialEntry == null ? '新增紀錄' : '編輯紀錄',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('收入'),
                    icon: Icon(Icons.trending_up),
                  ),
                  ButtonSegment(
                    value: TransactionType.saving,
                    label: Text('存款'),
                    icon: Icon(Icons.savings_outlined),
                  ),
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('支出'),
                    icon: Icon(Icons.trending_down),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  setState(() {
                    _type = selection.first;
                    _sourceController.clear();
                    _categoryController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: '金額',
                  prefixText: widget.currencySettings.symbol,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '請輸入金額';
                  }
                  final parsed =
                      double.tryParse(value.replaceAll(',', '').trim());
                  if (parsed == null || parsed <= 0) {
                    return '金額需為正數';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today),
                label: Text('日期：${dateFormat.format(_selectedDate)}'),
              ),
              const SizedBox(height: 12),
              if (_type != TransactionType.expense)
                _buildSelectionField(
                  label: '來源',
                  hint: '選擇或新增來源',
                  options: _type == TransactionType.income
                      ? _incomeOptions
                      : _savingOptions,
                  controller: _sourceController,
                  type: _type,
                ),
              if (_type == TransactionType.expense)
                _buildSelectionField(
                  label: '類別',
                  hint: '選擇或新增類別',
                  options: _expenseOptions,
                  controller: _categoryController,
                  type: TransactionType.expense,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: '備註',
                ),
                maxLines: 2,
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
                      child: Text(widget.initialEntry == null ? '儲存' : '更新'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionField({
    required String label,
    required String hint,
    required List<String> options,
    required TextEditingController controller,
    required TransactionType type,
  }) {
    final items = [
      ...options.map(
        (value) => DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        ),
      ),
      const DropdownMenuItem<String>(
        value: _customValueKey,
        child: Text('新增自訂項目…'),
      ),
    ];

    return DropdownButtonFormField<String>(
      key: ValueKey('${label}_${type.name}_${controller.text}_${options.length}'),
      initialValue: controller.text.isNotEmpty && options.contains(controller.text)
          ? controller.text
          : null,
      items: items,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
      onChanged: (value) async {
        if (value == null) return;
        if (value == _customValueKey) {
          final customValue = await _promptCustomValue(type, label);
          if (customValue != null) {
            controller.text = customValue;
            setState(() {});
          }
        } else {
          controller.text = value;
          setState(() {});
        }
      },
      validator: (value) {
        if (controller.text.isEmpty) {
          return '請選擇或新增$label';
        }
        return null;
      },
    );
  }

  Future<String?> _promptCustomValue(TransactionType type, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('新增$label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: label),
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

    if (result != null && result.trim().isNotEmpty) {
      final trimmed = result.trim();
      await widget.onCreateCategory?.call(type, trimmed);
      setState(() {
        switch (type) {
          case TransactionType.income:
            if (!_incomeOptions.contains(trimmed)) {
              _incomeOptions = [..._incomeOptions, trimmed];
            }
            break;
          case TransactionType.saving:
            if (!_savingOptions.contains(trimmed)) {
              _savingOptions = [..._savingOptions, trimmed];
            }
            break;
          case TransactionType.expense:
            if (!_expenseOptions.contains(trimmed)) {
              _expenseOptions = [..._expenseOptions, trimmed];
            }
            break;
        }
      });
      return trimmed;
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final amount =
        double.parse(_amountController.text.replaceAll(',', '').trim());
    final storedAmount = widget.currencySettings.toStorage(amount);
    final entry = MoneyEntry(
      id: widget.initialEntry?.id ??
          '${_type.name}_${DateTime.now().microsecondsSinceEpoch.toString()}',
      type: _type,
      amount: storedAmount,
      date: _selectedDate,
      source: _type == TransactionType.expense
          ? null
          : (_sourceController.text.isEmpty
              ? null
              : _sourceController.text.trim()),
      category: _type == TransactionType.saving
          ? null
          : (_categoryController.text.isEmpty
              ? null
              : _categoryController.text.trim()),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    Navigator.of(context).pop(entry);
  }
}

