// ============================================================
//  SpendWise - Expense Tracker (single file, NO extra packages)
//  Put this in: lib/main.dart
//  Requires Dart 3 / Flutter 3.10 or newer.
// ============================================================

import 'package:flutter/material.dart';

// ============================================================
//  1. HELPER FUNCTIONS (replace the intl package)
// ============================================================

// Converts paise to Indian format, e.g. 15000000 -> ₹1,50,000.00
String formatRupees(int paise) {
  final rupees = (paise ~/ 100).toString();
  final fraction = (paise % 100).toString().padLeft(2, '0');

  String grouped = rupees;

  // Indian grouping: last 3 digits, then groups of 2.
  if (rupees.length > 3) {
    final last3 = rupees.substring(rupees.length - 3);
    var rest = rupees.substring(0, rupees.length - 3);
    final parts = <String>[];

    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);

    grouped = '${parts.join(',')},$last3';
  }

  return '₹$grouped.$fraction';
}

const List<String> _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _longMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// 03 Nov 2026
String formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  return '$day ${_shortMonths[d.month - 1]} ${d.year}';
}

// 03 November 2026
String formatDateLong(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  return '$day ${_longMonths[d.month - 1]} ${d.year}';
}

// ============================================================
//  2. MODEL
//  One expense. The amount is stored in paise (integer) to
//  avoid decimal rounding errors. 100 paise = ₹1.
// ============================================================

class Expense {
  final String id;
  final String title;
  final String category;
  final int amountPaise;
  final DateTime date;
  final String note;

  const Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amountPaise,
    required this.date,
    this.note = '',
  });
}

// ============================================================
//  3. STORAGE SERVICE (in-memory, replaces shared_preferences)
//  Data lives only while the app process is running.
// ============================================================

class ExpenseStorage {
  static final List<Expense> _memory = [];

  Future<List<Expense>> loadExpenses() async {
    return List<Expense>.from(_memory);
  }

  Future<void> saveExpenses(List<Expense> expenses) async {
    _memory
      ..clear()
      ..addAll(expenses);
  }
}

// ============================================================
//  4. STATE MANAGEMENT
//  ExpenseProvider holds the data. ExpenseScope (below) makes
//  it available to every screen, replacing the provider package.
// ============================================================

// The 4 states the home screen can show.
enum ExpenseLoadState { loading, error, empty, data }

class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider({ExpenseStorage? storage})
      : _storage = storage ?? ExpenseStorage();

  final ExpenseStorage _storage;
  final List<Expense> _expenses = [];

  ExpenseLoadState _loadState = ExpenseLoadState.loading;
  String? _errorMessage;
  bool _busy = false; // prevents two saves/deletes at the same time

  // Expenses sorted newest first.
  List<Expense> get expenses {
    final list = List<Expense>.from(_expenses);
    list.sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(list);
  }

  ExpenseLoadState get loadState => _loadState;

  String? get errorMessage => _errorMessage;

  bool get isBusy => _busy;

  // Sum of all expenses in paise.
  int get totalPaise {
    return _expenses.fold(0, (sum, e) => sum + e.amountPaise);
  }

  // Load saved expenses.
  Future<void> loadExpenses() async {
    _loadState = ExpenseLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final loaded = await _storage.loadExpenses();

      _expenses
        ..clear()
        ..addAll(loaded);

      _updateState();
    } catch (_) {
      _loadState = ExpenseLoadState.error;
      _errorMessage = 'Could not load expenses. Please retry.';
    }

    notifyListeners();
  }

  // Add a new expense or update an existing one (matched by id).
  // Returns true on success, false on failure (changes are rolled back).
  Future<bool> saveExpense(Expense expense) async {
    if (_busy) return false;

    _busy = true;

    final previous = List<Expense>.from(_expenses);
    final index = _expenses.indexWhere((item) => item.id == expense.id);

    if (index >= 0) {
      _expenses[index] = expense;
    } else {
      _expenses.add(expense);
    }

    notifyListeners();

    try {
      await _storage.saveExpenses(_expenses);
      _errorMessage = null;
      _updateState();
      return true;
    } catch (_) {
      _expenses
        ..clear()
        ..addAll(previous);
      _errorMessage = 'Could not save the expense.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // Delete an expense by id.
  // Returns true on success, false on failure (changes are rolled back).
  Future<bool> deleteExpense(String id) async {
    if (_busy) return false;

    _busy = true;

    final previous = List<Expense>.from(_expenses);
    _expenses.removeWhere((expense) => expense.id == id);

    notifyListeners();

    try {
      await _storage.saveExpenses(_expenses);
      _errorMessage = null;
      _updateState();
      return true;
    } catch (_) {
      _expenses
        ..clear()
        ..addAll(previous);
      _errorMessage = 'Could not delete the expense.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // Decide between "empty" and "data" after the list changes.
  void _updateState() {
    _loadState =
        _expenses.isEmpty ? ExpenseLoadState.empty : ExpenseLoadState.data;
  }
}

// Makes ExpenseProvider available to the whole widget tree.
class ExpenseScope extends InheritedNotifier<ExpenseProvider> {
  const ExpenseScope({
    super.key,
    required ExpenseProvider provider,
    required super.child,
  }) : super(notifier: provider);

  // Use inside build(): the screen rebuilds when data changes.
  static ExpenseProvider watch(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ExpenseScope>()!
        .notifier!;
  }

  // Use inside button handlers: no rebuild.
  static ExpenseProvider read(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<ExpenseScope>()!;
    return (element.widget as ExpenseScope).notifier!;
  }
}

// ============================================================
//  5. APP ENTRY POINT
// ============================================================

void main() => runApp(const SpendWiseApp());

class SpendWiseApp extends StatefulWidget {
  const SpendWiseApp({super.key});

  @override
  State<SpendWiseApp> createState() => _SpendWiseAppState();
}

class _SpendWiseAppState extends State<SpendWiseApp> {
  // Created once; loadExpenses() runs at startup.
  final ExpenseProvider _provider = ExpenseProvider()..loadExpenses();

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExpenseScope(
      provider: _provider,
      child: MaterialApp(
        title: 'SpendWise',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

// ============================================================
//  6. WIDGET: EXPENSE CARD
//  One row in the list: category icon, title, date, amount.
// ============================================================

class ExpenseCard extends StatelessWidget {
  final Expense expense;
  final VoidCallback onTap;

  const ExpenseCard({
    super.key,
    required this.expense,
    required this.onTap,
  });

  // Pick an icon based on the category name.
  IconData get categoryIcon {
    switch (expense.category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'travel':
        return Icons.directions_bus;
      case 'shopping':
        return Icons.shopping_bag;
      case 'education':
        return Icons.school;
      case 'health':
        return Icons.medical_services;
      case 'bills':
        return Icons.receipt_long;
      default:
        return Icons.payments;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(child: Icon(categoryIcon)),
        title: Text(
          expense.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('${expense.category} • ${formatDate(expense.date)}'),
        trailing: Text(
          formatRupees(expense.amountPaise),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================
//  7. SCREEN: HOME
//  Total, list of expenses and the Add button.
//  Swipe left on an item to delete it (with Undo).
// ============================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Open the "Add Expense" form.
  Future<void> _openAddExpense(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
    );
  }

  // Open details (only the id is passed so it always shows fresh data).
  Future<void> _openDetails(BuildContext context, Expense expense) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailScreen(expenseId: expense.id),
      ),
    );
  }

  // Delete from the list and show a snackbar with Undo.
  Future<void> _deleteExpense(BuildContext context, Expense expense) async {
    // Grab these BEFORE the await so we never use a stale context.
    final messenger = ScaffoldMessenger.of(context);
    final provider = ExpenseScope.read(context);

    final deleted = await provider.deleteExpense(expense.id);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? '${expense.title} deleted'
              : 'Could not delete expense. Please try again.',
        ),
        action: deleted
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () => provider.saveExpense(expense),
              )
            : null,
      ),
    );
  }

  // --- UI for each state ---

  Widget _loadingState() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _errorState(ExpenseProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Unable to load expenses.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: provider.loadExpenses,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 64),
            const SizedBox(height: 16),
            Text(
              'No expenses yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first expense to start tracking your spending.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openAddExpense(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expenseList(BuildContext context, List<Expense> expenses) {
    return ListView.builder(
      itemCount: expenses.length,
      padding: const EdgeInsets.only(bottom: 90), // space for the button
      itemBuilder: (context, index) {
        final expense = expenses[index];

        return Dismissible(
          key: ValueKey(expense.id),
          direction: DismissDirection.endToStart, // swipe right-to-left
          background: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.only(right: 20),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          // Delete through the provider, then return false so Flutter does
          // not remove the row itself (the provider rebuilds the list).
          confirmDismiss: (_) async {
            await _deleteExpense(context, expense);
            return false;
          },
          child: ExpenseCard(
            expense: expense,
            onTap: () => _openDetails(context, expense),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = ExpenseScope.watch(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SpendWise'),
        actions: [
          IconButton(
            tooltip: 'Category Summary',
            icon: const Icon(Icons.pie_chart_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SummaryScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Total expenses card at the top.
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Expenses'),
                        const SizedBox(height: 4),
                        Text(
                          formatRupees(provider.totalPaise),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Body changes based on the provider state.
          Expanded(
            child: switch (provider.loadState) {
              ExpenseLoadState.loading => _loadingState(),
              ExpenseLoadState.error => _errorState(provider),
              ExpenseLoadState.empty => _emptyState(context),
              ExpenseLoadState.data =>
                _expenseList(context, provider.expenses),
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddExpense(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }
}

// ============================================================
//  8. SCREEN: ADD / EDIT EXPENSE FORM
//  If `expense` is null -> Add mode. Otherwise -> Edit mode.
// ============================================================

class ExpenseFormScreen extends StatefulWidget {
  final Expense? expense;

  const ExpenseFormScreen({super.key, this.expense});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  static const List<String> _categories = [
    'Food',
    'Travel',
    'Shopping',
    'Education',
    'Health',
    'Bills',
    'Other',
  ];

  late String _selectedCategory;
  late DateTime _selectedDate;

  bool _isSaving = false;

  bool get _isEditing => widget.expense != null;

  @override
  void initState() {
    super.initState();

    final expense = widget.expense;

    // Pre-fill the fields when editing.
    _titleController = TextEditingController(text: expense?.title ?? '');
    _amountController = TextEditingController(
      text: expense == null
          ? ''
          : (expense.amountPaise / 100).toStringAsFixed(2),
    );
    _noteController = TextEditingController(text: expense?.note ?? '');

    // Unknown saved category -> 'Other', so the dropdown never crashes.
    _selectedCategory =
        (expense != null && _categories.contains(expense.category))
            ? expense.category
            : (expense == null ? 'Food' : 'Other');
    _selectedDate = expense?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // Open the calendar. Future dates are not allowed.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate.isAfter(now) ? now : _selectedDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: now,
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  // --- Validation ---

  String? _validateTitle(String? value) {
    final title = value?.trim() ?? '';

    if (title.isEmpty) return 'Please enter an expense name';
    if (title.length > 80) return 'Name must be 80 characters or less';

    return null;
  }

  // Converts "150", "150.5" or "150.50" to paise using integer math
  // (no floating-point errors). Returns null if the text is invalid.
  int? _parsePaise(String? value) {
    final text = value?.trim() ?? '';
    final match = RegExp(r'^(\d{1,8})(?:\.(\d{1,2}))?$').firstMatch(text);

    if (match == null) return null;

    final rupees = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');

    return rupees * 100 + int.parse(fraction);
  }

  String? _validateAmount(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Please enter an amount';

    final paise = _parsePaise(value);

    if (paise == null) {
      return 'Enter a valid amount (up to 2 decimal places)';
    }

    if (paise <= 0) return 'Amount must be greater than zero';

    return null;
  }

  // --- Save ---

  Future<void> _saveExpense() async {
    if (_isSaving) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final amountPaise = _parsePaise(_amountController.text);
    if (amountPaise == null) return;

    setState(() => _isSaving = true);

    final newExpense = Expense(
      // Keep the old id when editing, create a new one when adding.
      id: widget.expense?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      category: _selectedCategory,
      amountPaise: amountPaise,
      date: _selectedDate,
      note: _noteController.text.trim(),
    );

    // Grab these BEFORE the await so we never use a stale context.
    final messenger = ScaffoldMessenger.of(context);
    final provider = ExpenseScope.read(context);
    var saved = false;

    try {
      saved = await provider.saveExpense(newExpense);
    } catch (_) {
      saved = false;
    }

    if (!mounted) return;

    // Success -> close the form.
    if (saved) {
      Navigator.pop(context, true);
      return;
    }

    // Failure -> stay on the form and show an error.
    setState(() => _isSaving = false);

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not save expense. Please try again.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Expense' : 'Add Expense'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Expense name
                TextFormField(
                  controller: _titleController,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Expense Name',
                    hintText: 'Example: Lunch',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateTitle,
                ),
                const SizedBox(height: 16),

                // Amount
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    hintText: 'Example: 150.00',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 16),

                // Category dropdown
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Date picker
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Expense Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    child: Text(formatDate(_selectedDate)),
                  ),
                ),
                const SizedBox(height: 16),

                // Optional note
                TextFormField(
                  controller: _noteController,
                  maxLength: 300,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (Optional)',
                    hintText: 'Add some details',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),

                // Save button (shows a spinner while saving)
                FilledButton(
                  onPressed: _isSaving ? null : _saveExpense,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Update Expense' : 'Save Expense'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  9. SCREEN: EXPENSE DETAILS
//  Shows all fields of one expense with Edit and Delete buttons.
//  It reads the expense live from the provider by id, so it
//  updates automatically after an edit.
// ============================================================

class ExpenseDetailScreen extends StatelessWidget {
  final String expenseId;

  const ExpenseDetailScreen({
    super.key,
    required this.expenseId,
  });

  // Find this expense in the current list (null if it was deleted).
  Expense? _find(List<Expense> expenses) {
    for (final item in expenses) {
      if (item.id == expenseId) return item;
    }
    return null;
  }

  // Open the form in Edit mode.
  Future<void> _editExpense(BuildContext context, Expense expense) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(expense: expense),
      ),
    );
  }

  // Ask for confirmation, then delete and go back.
  Future<void> _deleteExpense(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Expense?'),
          content: const Text('Are you sure you want to delete this expense?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final provider = ExpenseScope.read(context);

    final deleted = await provider.deleteExpense(expenseId);

    if (!context.mounted) return;

    if (deleted) {
      Navigator.pop(context, true);
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not delete expense. Please try again.'),
        ),
      );
    }
  }

  // One "label: value" row.
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expense = _find(ExpenseScope.watch(context).expenses);

    // The expense was deleted: show an empty page while the screen closes.
    if (expense == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expense Details')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Details'),
        actions: [
          IconButton(
            tooltip: 'Edit expense',
            onPressed: () => _editExpense(context, expense),
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Delete expense',
            onPressed: () => _deleteExpense(context),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: icon, amount, title
                  Center(
                    child: Column(
                      children: [
                        const Icon(Icons.account_balance_wallet, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          formatRupees(expense.amountPaise),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          expense.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),

                  // Details
                  _detailRow('Category', expense.category),
                  _detailRow('Date', formatDateLong(expense.date)),
                  _detailRow(
                    'Note',
                    expense.note.trim().isEmpty
                        ? 'No note added'
                        : expense.note,
                  ),
                  _detailRow('Expense ID', expense.id),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  10. SCREEN: CATEGORY SUMMARY
//  Total spending and a progress bar per category,
//  sorted from highest to lowest.
// ============================================================

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = ExpenseScope.watch(context);
    final expenses = provider.expenses;

    // Add up the amounts for each category.
    final Map<String, int> categoryTotals = {};

    for (final expense in expenses) {
      categoryTotals.update(
        expense.category,
        (value) => value + expense.amountPaise,
        ifAbsent: () => expense.amountPaise,
      );
    }

    // Sort categories by amount, highest first.
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = provider.totalPaise;

    return Scaffold(
      appBar: AppBar(title: const Text('Category Summary')),
      body: expenses.isEmpty
          ? const Center(
              child: Text('No expenses available to summarize.'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Total spending card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('Total Spending'),
                        const SizedBox(height: 8),
                        Text(
                          formatRupees(total),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Spending by Category',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),

                // One card per category with a percentage bar
                ...sortedCategories.map((entry) {
                  final percentage = total == 0 ? 0.0 : entry.value / total;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(formatRupees(entry.value)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: percentage,
                            minHeight: 8,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(percentage * 100).toStringAsFixed(1)}% of total',
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
