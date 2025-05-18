import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'bus_tracking_screen.dart';

class DriverDashboardScreen extends StatelessWidget {
  final String busId;

  const DriverDashboardScreen({super.key, required this.busId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Driver Dashboard - Bus $busId")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BusTrackingScreen(busId: busId),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text("Start Tracking"),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _sendAlert(context, "Breakdown"),
              icon: const Icon(Icons.warning),
              label: const Text("Report Breakdown"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => _sendAlert(context, "Route Change"),
              icon: const Icon(Icons.map),
              label: const Text("Report Route Change"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendAlert(BuildContext context, String alertType) async {
    try {
      final DatabaseReference db = FirebaseDatabase.instance.ref();
      final tokensSnapshot = await db.child('students').get();

      List<String> tokens = [];
      for (var student in tokensSnapshot.children) {
        final token = student.child('fcmToken').value;
        if (token != null && token.toString().isNotEmpty) {
          tokens.add(token.toString());
        }
      }

      // Update Firebase bus status
      await db.child('buses/$busId/status').set(alertType);

      // Send notifications
      for (String token in tokens) {
        await _sendPushNotification(token, alertType);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🚨 $alertType alert sent to students!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending alert: $e")),
      );
    }
  }

  Future<void> _sendPushNotification(String token, String alertType) async {
    const String serverKey = 'YOUR_FCM_SERVER_KEY'; // Replace with your key
    final Uri fcmUrl = Uri.parse('https://fcm.googleapis.com/fcm/send');

    await http.post(
      fcmUrl,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'key=$serverKey',
      },
      body: jsonEncode({
        "to": token,
        "notification": {
          "title": "Bus Alert: $alertType",
          "body": "Bus $busId has reported a $alertType.",
        },
        "data": {
          "type": alertType,
          "busId": busId,
        }
      }),
    );
  }
}