import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class CouchbaseLiteP2p {
  static const MethodChannel _channel = MethodChannel('couchbase_lite_p2p');

  final StreamController<Map<String, dynamic>> _p2pStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _syncGatewayStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<void> _workOrdersChangedController =
      StreamController<void>.broadcast();
  final StreamController<void> _workLogsChangedController =
      StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get onP2PStatusChanged =>
      _p2pStatusController.stream;
  Stream<Map<String, dynamic>> get onSyncGatewayStatusChanged =>
      _syncGatewayStatusController.stream;
  Stream<void> get onWorkOrdersChanged => _workOrdersChangedController.stream;
  Stream<void> get onWorkLogsChanged => _workLogsChangedController.stream;

  CouchbaseLiteP2p() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onP2PStatusChanged':
        _p2pStatusController
            .add(Map<String, dynamic>.from(call.arguments as Map));
        break;
      case 'onSyncGatewayStatusChanged':
        _syncGatewayStatusController
            .add(Map<String, dynamic>.from(call.arguments as Map));
        break;
      case 'onWorkOrdersChanged':
        _workOrdersChangedController.add(null);
        break;
      case 'onWorkLogsChanged':
        _workLogsChangedController.add(null);
        break;
    }
  }

  // --- Work Orders ---

  Future<List<Map<String, dynamic>>> getWorkOrders({String? status}) async {
    final List<dynamic> result = await _channel.invokeMethod('getWorkOrders', {
      if (status != null) 'status': status,
    });
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> getWorkOrder(String id) async {
    final result =
        await _channel.invokeMethod('getWorkOrder', {'id': id});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> updateWorkOrderStatus(String id, String status) async {
    await _channel
        .invokeMethod('updateWorkOrderStatus', {'id': id, 'status': status});
  }

  // --- Instructions ---

  Future<List<Map<String, dynamic>>> getInstructions(
      String workOrderId) async {
    final List<dynamic> result = await _channel
        .invokeMethod('getInstructions', {'workOrderId': workOrderId});
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // --- Work Logs ---

  Future<List<Map<String, dynamic>>> getWorkLogs(String workOrderId) async {
    final List<dynamic> result = await _channel
        .invokeMethod('getWorkLogs', {'workOrderId': workOrderId});
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<String> saveWorkLog(Map<String, dynamic> data) async {
    final String result =
        await _channel.invokeMethod('saveWorkLog', {'data': data});
    return result;
  }

  // --- Photos ---

  Future<String> savePhoto(
      String workLogId, Uint8List photoBytes, String caption) async {
    final String result = await _channel.invokeMethod('savePhoto', {
      'workLogId': workLogId,
      'photoBytes': photoBytes,
      'caption': caption,
    });
    return result;
  }

  Future<List<Map<String, dynamic>>> getPhotos(String workLogId) async {
    final List<dynamic> result =
        await _channel.invokeMethod('getPhotos', {'workLogId': workLogId});
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // --- Sync ---

  Future<bool> startP2P() async {
    final bool result = await _channel.invokeMethod('startP2P');
    return result;
  }

  Future<Map<String, dynamic>> getP2PStatus() async {
    final Map<dynamic, dynamic> result =
        await _channel.invokeMethod('getP2PStatus');
    return Map<String, dynamic>.from(result);
  }

  Future<bool> startSyncGatewayReplication(String url) async {
    final bool result = await _channel
        .invokeMethod('startSyncGatewayReplication', {'url': url});
    return result;
  }

  // --- Demo ---

  Future<void> seedDemoData() async {
    await _channel.invokeMethod('seedDemoData');
  }

  void dispose() {
    _p2pStatusController.close();
    _syncGatewayStatusController.close();
    _workOrdersChangedController.close();
    _workLogsChangedController.close();
  }
}
