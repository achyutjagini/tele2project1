import 'package:flutter/material.dart';
import 'package:couchbase_lite_p2p/couchbase_lite_p2p.dart';
import '../theme.dart';
import 'add_work_log_screen.dart';

class WorkOrderDetailScreen extends StatefulWidget {
  final CouchbaseLiteP2p db;
  final String workOrderId;
  final String technicianId;
  final bool isOnline;

  const WorkOrderDetailScreen({
    super.key,
    required this.db,
    required this.workOrderId,
    required this.technicianId,
    this.isOnline = true,
  });

  @override
  State<WorkOrderDetailScreen> createState() => _WorkOrderDetailScreenState();
}

class _WorkOrderDetailScreenState extends State<WorkOrderDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _workOrder;
  List<Map<String, dynamic>> _instructions = [];
  List<Map<String, dynamic>> _workLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadData();
    widget.db.onWorkLogsChanged.listen((_) => _loadWorkLogs());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadWorkOrder(),
      _loadInstructions(),
      _loadWorkLogs(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadWorkOrder() async {
    final order = await widget.db.getWorkOrder(widget.workOrderId);
    if (mounted) setState(() => _workOrder = order);
  }

  Future<void> _loadInstructions() async {
    final instructions =
        await widget.db.getInstructions(widget.workOrderId);
    if (mounted) setState(() => _instructions = instructions);
  }

  Future<void> _loadWorkLogs() async {
    final logs = await widget.db.getWorkLogs(widget.workOrderId);
    if (mounted) setState(() => _workLogs = logs);
  }

  Future<void> _updateStatus(String newStatus) async {
    await widget.db.updateWorkOrderStatus(widget.workOrderId, newStatus);
    await _loadWorkOrder();

    if (mounted) {
      final label = newStatus == 'in_progress' ? 'Started' : 'Completed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                widget.isOnline ? Icons.cloud_done : Icons.save,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Work order marked as $label',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      widget.isOnline
                          ? 'Syncing to cloud...'
                          : 'Saved locally. Will sync when back online.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: widget.isOnline ? Colors.green : tele2Purple,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_workOrder == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Work order not found')),
      );
    }

    final status = _workOrder!['status'] as String? ?? 'pending';

    return Scaffold(
      appBar: AppBar(
        title: Text(_workOrder!['title'] as String? ?? 'Work Order'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: tele2Purple,
          labelColor: tele2Purple,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Details'),
            Tab(icon: Icon(Icons.list_alt), text: 'Instructions'),
            Tab(icon: Icon(Icons.note_alt_outlined), text: 'Work Log'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDetailsTab(),
          _buildInstructionsTab(),
          _buildWorkLogsTab(),
        ],
      ),
      floatingActionButton: _buildFAB(status),
    );
  }

  Widget _buildDetailsTab() {
    final wo = _workOrder!;
    final status = wo['status'] as String? ?? 'pending';
    final priority = wo['priority'] as String? ?? 'medium';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status and priority row
          Row(
            children: [
              _statusChip(status),
              const SizedBox(width: 8),
              _priorityChip(priority),
              const Spacer(),
              if (status == 'pending')
                FilledButton.icon(
                  onPressed: () => _updateStatus('in_progress'),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tele2Purple,
                  ),
                ),
              if (status == 'in_progress')
                FilledButton.icon(
                  onPressed: () => _updateStatus('completed'),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Complete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Description
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Description',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                    wo['description'] as String? ?? 'No description',
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey[400], height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Customer & Location info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _detailRow(Icons.person_outline, 'Customer',
                      wo['customer_name'] as String? ?? '-'),
                  const Divider(height: 20),
                  _detailRow(Icons.location_on_outlined, 'Address',
                      wo['address'] as String? ?? '-'),
                  const Divider(height: 20),
                  _detailRow(Icons.schedule, 'Scheduled',
                      wo['scheduled_date'] as String? ?? '-'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Local storage indicator
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.storage, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Text(
                    'Available offline',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const Spacer(),
                  Icon(Icons.check_circle,
                      size: 16, color: Colors.green[400]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsTab() {
    if (_instructions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('No instructions available',
                style: TextStyle(fontSize: 16, color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _instructions.length,
      itemBuilder: (context, index) {
        final inst = _instructions[index];
        return _InstructionStep(
          stepNumber: inst['step_number'] as int? ?? (index + 1),
          title: inst['title'] as String? ?? 'Step ${index + 1}',
          description: inst['description'] as String? ?? '',
          isLast: index == _instructions.length - 1,
        );
      },
    );
  }

  Widget _buildWorkLogsTab() {
    return Column(
      children: [
        if (_workLogs.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.note_add_outlined,
                      size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text('No work logs yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                  const SizedBox(height: 8),
                  Text('Tap + to add your first log entry',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _workLogs.length,
              itemBuilder: (context, index) {
                final log = _workLogs[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.schedule,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              log['created_at'] as String? ?? '',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                            const Spacer(),
                            Icon(Icons.save,
                                size: 12, color: Colors.grey[600]),
                            const SizedBox(width: 2),
                            Text(
                              'Stored locally',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        if (log['work_done'] != null &&
                            (log['work_done'] as String).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Work Done',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.grey[400]),
                          ),
                          const SizedBox(height: 4),
                          Text(log['work_done'] as String),
                        ],
                        if (log['notes'] != null &&
                            (log['notes'] as String).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Notes',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.grey[400]),
                          ),
                          const SizedBox(height: 4),
                          Text(log['notes'] as String),
                        ],
                        if (log['photo_ids'] != null &&
                            (log['photo_ids'] as List).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.photo_library,
                                  size: 14, color: tele2LightPurple),
                              const SizedBox(width: 4),
                              Text(
                                '${(log['photo_ids'] as List).length} photo(s)',
                                style: const TextStyle(
                                    fontSize: 12, color: tele2LightPurple),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget? _buildFAB(String status) {
    if (_tabController.index != 2) return null;
    if (status == 'completed') return null;

    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.of(context)
            .push(
          MaterialPageRoute(
            builder: (_) => AddWorkLogScreen(
              db: widget.db,
              workOrderId: widget.workOrderId,
              technicianId: widget.technicianId,
              isOnline: widget.isOnline,
            ),
          ),
        )
            .then((_) => _loadWorkLogs());
      },
      backgroundColor: tele2Purple,
      icon: const Icon(Icons.add),
      label: const Text('Add Log'),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: tele2LightPurple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = Colors.orange;
        label = 'Pending';
        break;
      case 'in_progress':
        color = Colors.blue;
        label = 'In Progress';
        break;
      case 'completed':
        color = Colors.green;
        label = 'Completed';
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    return Chip(
      label: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _priorityChip(String priority) {
    Color color;
    IconData icon;
    switch (priority) {
      case 'critical':
        color = Colors.red;
        icon = Icons.error;
        break;
      case 'high':
        color = Colors.orange;
        icon = Icons.arrow_upward;
        break;
      case 'medium':
        color = Colors.blue;
        icon = Icons.remove;
        break;
      default:
        color = Colors.grey;
        icon = Icons.arrow_downward;
    }
    return Chip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(priority[0].toUpperCase() + priority.substring(1),
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String description;
  final bool isLast;

  const _InstructionStep({
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: tele2Purple,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$stepNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: tele2Purple.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                            height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
