import 'package:flutter/material.dart';
import '../services/attendance_service.dart';
import '../utils/app_colors.dart';
import '../utils/time_utils.dart';

class AttendanceSidebarItem extends StatefulWidget {
  final String workerId;
  final String organizationCode;
  final bool isDarkMode;

  const AttendanceSidebarItem({
    super.key,
    required this.workerId,
    required this.organizationCode,
    required this.isDarkMode,
  });

  @override
  State<AttendanceSidebarItem> createState() => _AttendanceSidebarItemState();
}

class _AttendanceSidebarItemState extends State<AttendanceSidebarItem> {
  final AttendanceService _attendanceService = AttendanceService();
  Map<String, dynamic>? _attendance;
  List<Map<String, dynamic>> _shifts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final attendance = await _attendanceService.getTodayAttendance(
        widget.workerId,
        widget.organizationCode,
      );
      final shifts = await _attendanceService.fetchShifts(
        widget.organizationCode,
      );

      if (mounted) {
        setState(() {
          _attendance = attendance;
          _shifts = shifts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCheckInOut() async {
    setState(() => _isLoading = true);
    try {
      final isCheckOut =
          _attendance != null &&
          _attendance!['check_in'] != null &&
          _attendance!['check_out'] == null;

      await _attendanceService.updateAttendance(
        workerId: widget.workerId,
        organizationCode: widget.organizationCode,
        shifts: _shifts,
        isCheckOut: isCheckOut,
      );

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCheckOut
                  ? 'Checked Out Successfully'
                  : 'Checked In Successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _attendance == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final Color accentColor = AppColors.getAccent(widget.isDarkMode);
    final Color secondaryTextColor = AppColors.getSecondaryText(
      widget.isDarkMode,
    );
    final Color cardColor = AppColors.getCard(widget.isDarkMode);

    final checkIn = _attendance?['check_in'];
    final checkOut = _attendance?['check_out'];
    final status = _attendance?['status'] ?? 'Not Checked In';
    final shiftName = _attendance?['shift_name'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ATTENDANCE',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.login_rounded,
            'Check In',
            checkIn != null
                ? TimeUtils.formatTo12Hour(DateTime.parse(checkIn).toLocal())
                : '--:--',
            widget.isDarkMode,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.logout_rounded,
            'Check Out',
            checkOut != null
                ? TimeUtils.formatTo12Hour(DateTime.parse(checkOut).toLocal())
                : '--:--',
            widget.isDarkMode,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.schedule_rounded,
            'Shift',
            shiftName,
            widget.isDarkMode,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (checkIn != null && checkOut != null)
                  ? null
                  : _handleCheckInOut,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      checkIn == null
                          ? 'CHECK IN'
                          : (checkOut == null ? 'CHECK OUT' : 'COMPLETED'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    bool isDarkMode,
  ) {
    final Color textColor = AppColors.getText(isDarkMode);
    final Color secondaryTextColor = AppColors.getSecondaryText(isDarkMode);

    return Row(
      children: [
        Icon(icon, size: 16, color: secondaryTextColor),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(color: secondaryTextColor, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
