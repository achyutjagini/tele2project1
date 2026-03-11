import 'package:flutter/material.dart';
import 'package:couchbase_lite_p2p/couchbase_lite_p2p.dart';
import '../theme.dart';
import 'work_order_detail_screen.dart';

class WorkOrdersScreen extends StatefulWidget {
  final CouchbaseLiteP2p db;
  final String technicianId;
  final bool isOnline;

  const WorkOrdersScreen({
    super.key,
    required this.db,
    required this.technicianId,
    this.isOnline = true,
  });

  @override
  State<WorkOrdersScreen> createState() => _WorkOrdersScreenState();
}

class _WorkOrdersScreenState extends State<WorkOrdersScreen> {
  List<Map<String, dynamic>> _workOrders = [];
  String _selectedFilter = 'all';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkOrders();
    widget.db.onWorkOrdersChanged.listen((_) => _loadWorkOrders());
  }

  Future<void> _loadWorkOrders() async {
    try {
      final status = _selectedFilter == 'all' ? null : _selectedFilter;
      final orders = await widget.db.getWorkOrders(status: status);
      if (mounted) {
        setState(() {
          _workOrders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to load work orders: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _filterChip('All', 'all'),
              const SizedBox(width: 8),
              _filterChip('Pending', 'pending'),
              const SizedBox(width: 8),
              _filterChip('In Progress', 'in_progress'),
              const SizedBox(width: 8),
              _filterChip('Completed', 'completed'),
            ],
          ),
        ),
        // Work order count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${_workOrders.length} work order${_workOrders.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const Spacer(),
              Icon(Icons.storage, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'Stored locally',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Work order list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _workOrders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_outlined,
                              size: 64, color: Colors.grey[600]),
                          const SizedBox(height: 16),
                          Text(
                            'No work orders',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey[500]),
                          ),
                          if (!widget.isOnline) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Connect to the internet to download work orders',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadWorkOrders,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _workOrders.length,
                        itemBuilder: (context, index) {
                          return _WorkOrderCard(
                            workOrder: _workOrders[index],
                            onTap: () => _openDetail(_workOrders[index]),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedFilter = value);
        _loadWorkOrders();
      },
      selectedColor: tele2Purple,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      checkmarkColor: Colors.white,
    );
  }

  void _openDetail(Map<String, dynamic> workOrder) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => WorkOrderDetailScreen(
          db: widget.db,
          workOrderId: workOrder['id'] as String,
          technicianId: widget.technicianId,
          isOnline: widget.isOnline,
        ),
      ),
    )
        .then((_) => _loadWorkOrders());
  }
}

class _WorkOrderCard extends StatelessWidget {
  final Map<String, dynamic> workOrder;
  final VoidCallback onTap;

  const _WorkOrderCard({required this.workOrder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = workOrder['status'] as String? ?? 'pending';
    final priority = workOrder['priority'] as String? ?? 'medium';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _priorityIndicator(priority),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      workOrder['title'] as String? ?? 'Untitled',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 8),
              if (workOrder['address'] != null)
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        workOrder['address'] as String,
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              if (workOrder['customer_name'] != null)
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      workOrder['customer_name'] as String,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              if (workOrder['scheduled_date'] != null)
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(workOrder['scheduled_date'] as String),
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityIndicator(String priority) {
    Color color;
    switch (priority) {
      case 'critical':
        color = Colors.red;
        break;
      case 'high':
        color = Colors.orange;
        break;
      case 'medium':
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 4,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bgColor;
    Color textColor;
    String label;
    switch (status) {
      case 'pending':
        bgColor = Colors.orange.withValues(alpha: 0.2);
        textColor = Colors.orange;
        label = 'Pending';
        break;
      case 'in_progress':
        bgColor = Colors.blue.withValues(alpha: 0.2);
        textColor = Colors.blue;
        label = 'In Progress';
        break;
      case 'completed':
        bgColor = Colors.green.withValues(alpha: 0.2);
        textColor = Colors.green;
        label = 'Completed';
        break;
      default:
        bgColor = Colors.grey.withValues(alpha: 0.2);
        textColor = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = date.difference(now);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Tomorrow';
      if (diff.inDays == -1) return 'Yesterday';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }
}
