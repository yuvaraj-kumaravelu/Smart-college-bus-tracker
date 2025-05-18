import 'package:flutter/material.dart';
import 'student_tracking_screen.dart'; // Make sure this import is correct in your structure

class TrackingModeSelectorScreen extends StatelessWidget {
  final String busId;
  final String studentId;

  const TrackingModeSelectorScreen({
    Key? key,
    required this.busId,
    required this.studentId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Tracking Mode")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.directions_walk),
              label: const Text("Track My Movement (🧑‍🎓 → 🎯)"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentTrackingScreen(
                      busId: busId,
                      studentId: studentId,
                      initialTrackBus: false,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.directions_bus),
              label: const Text("Track Bus (🚌 → 🎯)"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentTrackingScreen(
                      busId: busId,
                      studentId: studentId,
                      initialTrackBus: true,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}