import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'DriverDashboardScreen.dart';
import 'student_tracking_screen.dart';
import 'TrackingModeSelectorScreen.dart';
import 'login_screen.dart';

class BusSelectionScreen extends StatefulWidget {
  final bool isDriver;

  const BusSelectionScreen({super.key, required this.isDriver});

  @override
  _BusSelectionScreenState createState() => _BusSelectionScreenState();
}

class _BusSelectionScreenState extends State<BusSelectionScreen> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref("buses");
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1D2B64), Color(0xFFf8cdda)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => LoginScreen()),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "Select Your Bus",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder(
                  stream: _database.onValue,
                  builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text("Error: ${snapshot.error}", style: TextStyle(color: Colors.white)));
                    }
                    if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                      return const Center(child: Text("No buses available", style: TextStyle(color: Colors.white)));
                    }

                    Object? rawData = snapshot.data!.snapshot.value;
                    if (rawData is! Map) {
                      return const Center(child: Text("Invalid bus data", style: TextStyle(color: Colors.white)));
                    }

                    Map<String, dynamic> buses = {};
                    rawData.forEach((key, value) {
                      if (key is String && value is Map) {
                        buses[key] = Map<String, dynamic>.from(value);
                      }
                    });

                    if (buses.isEmpty) {
                      return const Center(child: Text("No valid buses found", style: TextStyle(color: Colors.white)));
                    }

                    List<MapEntry<String, dynamic>> sortedBuses = buses.entries.toList()
                      ..sort((a, b) {
                        int etaA = int.tryParse(a.value["eta"]?.toString().split(" ")[0] ?? "9999") ?? 9999;
                        int etaB = int.tryParse(b.value["eta"]?.toString().split(" ")[0] ?? "9999") ?? 9999;
                        return etaA.compareTo(etaB);
                      });

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: sortedBuses.length,
                      itemBuilder: (context, index) {
                        String busId = sortedBuses[index].key;
                        Map<String, dynamic> busData = sortedBuses[index].value;

                        String eta = busData["eta"]?.toString() ?? "Unknown";
                        String status = busData["status"]?.toString() ?? "Unknown";
                        String driver = busData["driver"]?.toString() ?? "No driver assigned";
                        bool isBreakdown = status.toLowerCase() == "breakdown";

                        return Card(
                          color: Colors.white.withOpacity(0.9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 6,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(
                              "Bus $busId",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              "Driver: $driver\nETA: $eta",
                              style: const TextStyle(color: Colors.black54),
                            ),
                            leading: Icon(
                              isBreakdown ? Icons.warning_amber_rounded : Icons.directions_bus_filled_rounded,
                              color: isBreakdown ? Colors.red : Colors.teal,
                              size: 32,
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.black45),
                            onTap: () {
                              if (!isBreakdown) _selectBus(context, busId);
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectBus(BuildContext context, String busId) async {
    if (widget.isDriver) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => DriverDashboardScreen(busId: busId)),
      );
    } else {
      String studentId = await _getStudentId();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => TrackingModeSelectorScreen(busId: busId, studentId: studentId)),
      );
    }
  }

  Future<String> _getStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    String? cachedStudentId = prefs.getString('student_id');

    if (cachedStudentId != null) return cachedStudentId;

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Uuid().v4();

    DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
    String studentId = doc.exists ? (doc['studentId'] ?? const Uuid().v4()) : const Uuid().v4();
    await prefs.setString('student_id', studentId);

    return studentId;
  }
}
