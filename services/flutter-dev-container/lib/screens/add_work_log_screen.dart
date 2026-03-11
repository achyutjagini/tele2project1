import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:couchbase_lite_p2p/couchbase_lite_p2p.dart';
import '../theme.dart';

class AddWorkLogScreen extends StatefulWidget {
  final CouchbaseLiteP2p db;
  final String workOrderId;
  final String technicianId;
  final bool isOnline;

  const AddWorkLogScreen({
    super.key,
    required this.db,
    required this.workOrderId,
    required this.technicianId,
    this.isOnline = true,
  });

  @override
  State<AddWorkLogScreen> createState() => _AddWorkLogScreenState();
}

class _AddWorkLogScreenState extends State<AddWorkLogScreen>
    with TickerProviderStateMixin {
  final _workDoneController = TextEditingController();
  final _notesController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<_CapturedPhoto> _photos = [];
  bool _isSaving = false;

  // Speech-to-text
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _activeField = '';

  // Animations
  late AnimationController _pulseController;
  late AnimationController _saveController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initSpeech();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _saveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) {
        setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
    );
    setState(() {});
  }

  void _startListening(String field) {
    if (!_speechAvailable) {
      _showPremiumSnackBar(
        'Speech recognition not available on this device',
        Icons.mic_off_rounded,
        Colors.orange,
      );
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _isListening = true;
      _activeField = field;
    });

    _speech.listen(
      onResult: (result) {
        final controller =
            field == 'work_done' ? _workDoneController : _notesController;
        final current = controller.text;
        final newText = result.recognizedWords;

        if (result.finalResult) {
          controller.text =
              current.isEmpty ? newText : '$current $newText';
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  void _stopListening() {
    HapticFeedback.lightImpact();
    _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _workDoneController.dispose();
    _notesController.dispose();
    _speech.stop();
    _pulseController.dispose();
    _saveController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    HapticFeedback.selectionClick();
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _photos.add(_CapturedPhoto(bytes: bytes, caption: ''));
      });
    }
  }

  Future<void> _pickFromGallery() async {
    HapticFeedback.selectionClick();
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _photos.add(_CapturedPhoto(bytes: bytes, caption: ''));
      });
    }
  }

  void _showPremiumSnackBar(String message, IconData icon, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
      ),
    );
  }

  Future<void> _showSuccessPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) {
        return _SuccessPopupContent(
          isOnline: widget.isOnline,
          photoCount: _photos.length,
        );
      },
    );
  }

  Future<void> _save() async {
    if (_workDoneController.text.isEmpty && _notesController.text.isEmpty) {
      _showPremiumSnackBar(
        'Please describe the work done or add notes',
        Icons.edit_note_rounded,
        Colors.orange[700]!,
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    try {
      final logId = await widget.db.saveWorkLog({
        'work_order_id': widget.workOrderId,
        'technician_id': widget.technicianId,
        'work_done': _workDoneController.text,
        'notes': _notesController.text,
      });

      for (final photo in _photos) {
        await widget.db.savePhoto(logId, photo.bytes, photo.caption);
      }

      if (mounted) {
        HapticFeedback.heavyImpact();
        await _showSuccessPopup();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showPremiumSnackBar(
          'Failed to save: $e',
          Icons.error_outline_rounded,
          Colors.red[700]!,
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF242424) : Colors.white;
    final cardColor = isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF8F8FA);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final subtleText = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1E) : const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          // Premium App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            stretch: true,
            backgroundColor: surfaceColor,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: isDark ? Colors.white : tele2Black,
                    size: 20,
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
              title: Text(
                'New Work Log',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : tele2Black,
                  letterSpacing: -0.5,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  border: Border(
                    bottom: BorderSide(color: borderColor),
                  ),
                ),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48, right: 16),
                    child: _buildSyncBadge(isDark),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Offline notice
                if (!widget.isOnline) ...[
                  _buildOfflineBanner(isDark),
                  const SizedBox(height: 16),
                ],

                // Work Done Section
                _buildSectionCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  borderColor: borderColor,
                  subtleText: subtleText,
                  icon: Icons.build_rounded,
                  iconColor: tele2Purple,
                  label: 'Work Performed',
                  fieldName: 'work_done',
                  controller: _workDoneController,
                  hint: 'Describe what was done...',
                  maxLines: 5,
                ),
                const SizedBox(height: 16),

                // Notes Section
                _buildSectionCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  borderColor: borderColor,
                  subtleText: subtleText,
                  icon: Icons.sticky_note_2_rounded,
                  iconColor: const Color(0xFF6366F1),
                  label: 'Additional Notes',
                  fieldName: 'notes',
                  controller: _notesController,
                  hint: 'Observations, follow-ups, recommendations...',
                  maxLines: 4,
                ),
                const SizedBox(height: 16),

                // Photos Section
                _buildPhotosSection(isDark, cardColor, borderColor, subtleText),
              ]),
            ),
          ),
        ],
      ),

      // Premium Save Button
      bottomSheet: _buildSaveButton(isDark, surfaceColor, borderColor),
    );
  }

  Widget _buildSyncBadge(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (widget.isOnline ? Colors.green : Colors.orange)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (widget.isOnline ? Colors.green : Colors.orange)
              .withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.isOnline ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.isOnline ? Colors.green[400] : Colors.orange[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.withValues(alpha: 0.12),
            Colors.orange.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_off_rounded,
                size: 18, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Working Offline',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[300],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your log will be saved locally and synced automatically.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[400]?.withValues(alpha: 0.8),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
    required Color subtleText,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String fieldName,
    required TextEditingController controller,
    required String hint,
    required int maxLines,
  }) {
    final isActiveField = _isListening && _activeField == fieldName;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActiveField
              ? tele2Purple.withValues(alpha: 0.5)
              : borderColor,
          width: isActiveField ? 1.5 : 1,
        ),
        boxShadow: [
          if (isActiveField)
            BoxShadow(
              color: tele2Purple.withValues(alpha: 0.08),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                if (_speechAvailable) _buildDictateButton(fieldName, isActiveField),
              ],
            ),
          ),

          // Active Listening Indicator
          if (isActiveField)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: _buildListeningIndicator(),
            ),

          // Text Input
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark ? Colors.white.withValues(alpha: 0.9) : tele2Black,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: isDark
                      ? Colors.grey[600]
                      : Colors.grey[400],
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDictateButton(String fieldName, bool isActiveField) {
    return GestureDetector(
      onTap: () {
        if (isActiveField) {
          _stopListening();
        } else {
          _startListening(fieldName);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActiveField
              ? Colors.red.withValues(alpha: 0.12)
              : tele2Purple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActiveField
                ? Colors.red.withValues(alpha: 0.3)
                : tele2Purple.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActiveField)
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value * 0.85,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              )
            else
              Icon(Icons.mic_rounded, size: 15, color: tele2LightPurple),
            const SizedBox(width: 6),
            Text(
              isActiveField ? 'Listening...' : 'Dictate',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActiveField ? Colors.red[400] : tele2LightPurple,
              ),
            ),
            if (isActiveField) ...[
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: 14,
                color: Colors.red.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 6),
              Icon(Icons.stop_rounded, size: 15, color: Colors.red[400]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildListeningIndicator() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: tele2Purple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tele2Purple.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              // Audio waveform visualization
              ...List.generate(12, (i) {
                final offset = (i * 0.15) + _pulseController.value;
                final height = 4.0 + (sin(offset * 3.14 * 2) + 1) * 8;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 3,
                    height: height,
                    decoration: BoxDecoration(
                      color: tele2LightPurple.withValues(
                          alpha: 0.4 + (sin(offset * 3.14 * 2) + 1) * 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Speak now — tap Stop when done',
                  style: TextStyle(
                    fontSize: 12,
                    color: tele2LightPurple.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhotosSection(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color subtleText,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_camera_rounded,
                      size: 16, color: Color(0xFF10B981)),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Photos',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                if (_photos.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: tele2Purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_photos.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tele2LightPurple,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _buildPhotoActionButton(
                  Icons.camera_alt_rounded,
                  'Camera',
                  _takePhoto,
                ),
                const SizedBox(width: 6),
                _buildPhotoActionButton(
                  Icons.photo_library_rounded,
                  'Gallery',
                  _pickFromGallery,
                ),
              ],
            ),
          ),

          // Photo Grid or Empty State
          if (_photos.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: GestureDetector(
                onTap: _takePhoto,
                child: Container(
                  width: double.infinity,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.02)
                        : Colors.black.withValues(alpha: 0.02),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_rounded,
                          size: 28, color: subtleText),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to capture or select photos',
                        style: TextStyle(
                          color: subtleText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 110,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length + 1,
                itemBuilder: (context, index) {
                  if (index == _photos.length) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: _takePhoto,
                        child: Container(
                          width: 96,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded,
                                  size: 24, color: subtleText),
                              const SizedBox(height: 4),
                              Text('Add',
                                  style: TextStyle(
                                      fontSize: 11, color: subtleText)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
                    child: _buildPhotoThumbnail(index, isDark),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoActionButton(
      IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tele2Purple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tele2LightPurple),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tele2LightPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoThumbnail(int index, bool isDark) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            _photos[index].bytes,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
          ),
        ),
        // Gradient overlay at top for delete button
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _photos.removeAt(index));
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton(bool isDark, Color surfaceColor, Color borderColor) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(top: BorderSide(color: borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Info text
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.isOnline
                            ? Icons.cloud_done_rounded
                            : Icons.save_rounded,
                        size: 14,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.isOnline ? 'Will sync to cloud' : 'Saves locally',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (_photos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${_photos.length} photo${_photos.length > 1 ? 's' : ''} attached',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[600] : Colors.grey[500],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Save button
            GestureDetector(
              onTap: _isSaving ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isSaving
                        ? [Colors.grey, Colors.grey]
                        : [tele2Purple, tele2DarkPurple],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    if (!_isSaving)
                      BoxShadow(
                        color: tele2Purple.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Save Log',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapturedPhoto {
  final Uint8List bytes;
  final String caption;

  _CapturedPhoto({required this.bytes, required this.caption});
}

class _SuccessPopupContent extends StatefulWidget {
  final bool isOnline;
  final int photoCount;

  const _SuccessPopupContent({
    required this.isOnline,
    required this.photoCount,
  });

  @override
  State<_SuccessPopupContent> createState() => _SuccessPopupContentState();
}

class _SuccessPopupContentState extends State<_SuccessPopupContent>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late AnimationController _progressController;
  late Animation<double> _checkAnimation;
  late Animation<double> _progressAnimation;

  bool _synced = false;

  @override
  void initState() {
    super.initState();

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Play checkmark animation
    await Future.delayed(const Duration(milliseconds: 200));
    _checkController.forward();

    if (widget.isOnline) {
      // Simulate sync progress
      await Future.delayed(const Duration(milliseconds: 500));
      _progressController.forward();
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) setState(() => _synced = true);
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 1200));
    } else {
      await Future.delayed(const Duration(milliseconds: 2200));
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2E) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated checkmark circle
            ScaleTransition(
              scale: _checkAnimation,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _synced
                        ? [const Color(0xFF10B981), const Color(0xFF059669)]
                        : [tele2Purple, tele2DarkPurple],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_synced ? const Color(0xFF10B981) : tele2Purple)
                          .withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    _synced ? Icons.cloud_done_rounded : Icons.check_rounded,
                    key: ValueKey(_synced),
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _synced ? 'Synced to Cloud' : 'Work Log Saved',
                key: ValueKey(_synced ? 'synced' : 'saved'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : tele2Black,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _synced
                    ? 'Your work log is now available across all devices.'
                    : widget.isOnline
                        ? 'Syncing to cloud...'
                        : 'Saved locally. Will sync automatically when you\'re back online.',
                key: ValueKey('$_synced-${widget.isOnline}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ),

            // Sync progress bar (online only)
            if (widget.isOnline && !_synced) ...[
              const SizedBox(height: 20),
              AnimatedBuilder(
                animation: _progressAnimation,
                builder: (context, _) {
                  return Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progressAnimation.value,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: const LinearGradient(
                            colors: [tele2Purple, tele2LightPurple],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            // Photo count badge
            if (widget.photoCount > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_rounded,
                        size: 14,
                        color: isDark ? Colors.grey[500] : Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.photoCount} photo${widget.photoCount > 1 ? 's' : ''} included',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
