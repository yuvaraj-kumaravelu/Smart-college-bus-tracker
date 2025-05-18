import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'TrackingModeSelectorScreen.dart';
import 'bus_selection_screen.dart';


class StudentTrackingScreen extends StatefulWidget {
  final String busId;
  final String studentId;
  final bool initialTrackBus;

  const StudentTrackingScreen({
    Key? key,
    required this.busId,
    required this.studentId,
    this.initialTrackBus = false,
  }) : super(key: key);

  @override
  _StudentTrackingScreenState createState() => _StudentTrackingScreenState();
}

class _StudentTrackingScreenState extends State<StudentTrackingScreen> {
  late GoogleMapController _mapController;
  final Completer<GoogleMapController> _controller = Completer();
  late DatabaseReference _busRef;
  late DatabaseReference _studentRef;
  late Timer _updateTimer;
  Location _location = Location();
  LatLng? _lastBusLocation; // For bearing calculation


  LatLng? _busLocation;
  LatLng? _studentLocation;
  LatLng? _destination;
  List<Map<String, dynamic>> _stations = [];

  String _etaMessage = "";
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  StreamSubscription<DatabaseEvent>? _busSubscription;

  bool _trackBus = false;
  BitmapDescriptor? _arrowIcon;

  static const String _apiKey = "AIzaSyALIyJ73NuMuXfW29teqEN6YuI-_4y4EPA";

  @override
  void initState() {
    super.initState();
    _trackBus = widget.initialTrackBus;
    _busRef = FirebaseDatabase.instance.ref().child('buses/${widget.busId}');
    _studentRef = FirebaseDatabase.instance.ref().child('students/${widget.studentId}');

    _listenForDestinationUpdates();
    _startListeningForBusLocation();

    _loadArrowIcon();

    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_trackBus) {
        _updateStudentLocation();
      }
    });

    _getCurrentLocation();

    if (_trackBus) {
      _updateBusLocationOnce(); // 👈 New line: push current location to Firebase
    }
  }


  Future<void> _loadArrowIcon() async {
    final Uint8List arrowBytes =
    await rootBundle.load('assets/arrow.jpeg').then((value) => value.buffer.asUint8List());
    final compressedBytes = await FlutterImageCompress.compressWithList(
      arrowBytes,
      minWidth: 65,
      minHeight: 80,
      quality: 50,
      format: CompressFormat.jpeg,
    );
    setState(() {
      _arrowIcon = BitmapDescriptor.fromBytes(compressedBytes);
    });
  }



  Future<void> _getCurrentLocation() async {
    LocationData locationData = await _location.getLocation();
    setState(() {
      _studentLocation = LatLng(locationData.latitude!, locationData.longitude!);
    });
    _updateMap();
    _fetchETA();
    _getRoute();
  }

  Future<void> _updateStudentLocation() async {
    LocationData locationData = await _location.getLocation();
    LatLng newLocation = LatLng(locationData.latitude!, locationData.longitude!);

    setState(() {
      _studentLocation = newLocation;
    });

    await _studentRef.update({
      'latitude': newLocation.latitude,
      'longitude': newLocation.longitude,
    });

    _updateMap();
    _getRoute();
    _fetchETA();

  }
  Future<void> _updateBusLocationOnce() async {
    try {
      final locationData = await _location.getLocation();
      LatLng currentLoc = LatLng(locationData.latitude!, locationData.longitude!);

      await _busRef.update({
        'latitude': currentLoc.latitude,
        'longitude': currentLoc.longitude,
      });

      setState(() {
        _busLocation = currentLoc;
      });

      _updateMap();
      _getRoute();
      _fetchETA();
    } catch (e) {
      print('Failed to update bus location: $e');
    }
  }



  void _startListeningForBusLocation() {
    _busSubscription = _busRef.onValue.listen((event) {
      if (!event.snapshot.exists) return;

      Map<String, dynamic> data = Map<String, dynamic>.from(event.snapshot.value as Map);
      LatLng newBusLocation = LatLng(data["latitude"], data["longitude"]);

      double bearing = 0;
      if (_lastBusLocation != null) {
        bearing = Geolocator.bearingBetween(
          _lastBusLocation!.latitude, _lastBusLocation!.longitude,
          newBusLocation.latitude, newBusLocation.longitude,
        );
      }
      _lastBusLocation = newBusLocation;

      setState(() {
        _busLocation = newBusLocation;
      });

      _updateMap();
      _getRoute();
      _fetchETA();

    }, onError: (error) {
      print("❌ Error fetching bus location: $error");
    });
  }

  /// Replaces your one-time fetch. Listens for real-time updates!
  /// Listen to the full bus node to get both destination and stations
  void _listenForDestinationUpdates() {
    FirebaseDatabase.instance
        .ref('buses/${widget.busId}')
        .onValue
        .listen((event) {
      final raw = event.snapshot.value;
      print("🔥 Raw bus snapshot: $raw");
      if (raw == null) {
        print("⚠️ Bus node is null or missing!");
        return;
      }

      final busData = Map<String, dynamic>.from(raw as Map);

      // 1) Parse destination
      if (busData['destination'] == null) {
        print("⚠️ 'destination' key is missing on bus node!");
        return;
      }
      final destMap = Map<String, dynamic>.from(busData['destination']);
      final newDestination = LatLng(destMap['latitude'], destMap['longitude']);

      // 2) Parse stations (siblings of destination)
      if (busData['stations'] == null) {
        print("⚠️ 'stations' key is missing on bus node!");
        return;
      }
      // ✅ CORRECT: stations is a List of Maps
      final rawStations = busData['stations'] as List<dynamic>;
      final stationsList = rawStations
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      print("🔥 Loaded stationsList: $stationsList");

      // 3) Update state
      setState(() {
        _destination = newDestination;
        _stations    = stationsList;
      });

      _updateMap();
    }, onError: (e) {
      print("❌ Error listening to buses/${widget.busId}: $e");
    });
  }

  Future<void> _getRoute() async {
    if ((_trackBus && _busLocation == null) || (!_trackBus && _studentLocation == null) || _destination == null) return;

    LatLng start = _trackBus ? _busLocation! : _studentLocation!;
    LatLng end = _destination!;

    // OSRM API URL
    final Uri url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
            "${start.longitude},${start.latitude};"
            "${end.longitude},${end.latitude}"
            "?overview=full&geometries=geojson"
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data["routes"] != null && data["routes"].isNotEmpty) {
      final geometry = data["routes"][0]["geometry"];
      List coordinates = geometry["coordinates"];

      List<LatLng> polylinePoints = coordinates.map<LatLng>((coord) {
        return LatLng(coord[1], coord[0]); // [lng, lat] => LatLng
      }).toList();

      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId("route"),
            color: Colors.blue,
            width: 5,
            points: polylinePoints,
          ),
        };
      });
    } else {
      print("❌ Error fetching route: ${response.body}");
    }
  }
  Future<void> _fetchETA() async {
    if ((_trackBus && _busLocation == null) || (!_trackBus && _studentLocation == null) || _destination == null) return;

    LatLng start = _trackBus ? _busLocation! : _studentLocation!;
    LatLng end = _destination!;
    // OSRM API URL
    final Uri url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
            "${start.longitude},${start.latitude};"
            "${end.longitude},${end.latitude}?overview=false"
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data.containsKey("routes") && data["routes"].isNotEmpty) {
          int durationInSeconds = data["routes"][0]["duration"].toInt();
          int minutes = (durationInSeconds / 60).round();
          if (minutes == 0) minutes = 1; // Prevents showing 0 min

          setState(() => _etaMessage = "ETA: $minutes min");
        } else {
          print("❌ Error: No routes found in response.");
        }
      } else {
        print("❌ Error fetching ETA: ${response.statusCode}");
      }
    } on SocketException {
      print("❌ No internet connection");
    } on HttpException {
      print("❌ HTTP error");
    } on FormatException {
      print("❌ Invalid JSON format");
    } catch (e) {
      print("❌ Exception: $e");
    }
  }



  @override
  void dispose() {
    _busSubscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }
  void _updateMap() {
    Set<Marker> updatedMarkers = {};

    // Add Bus Marker
    if (_trackBus && _busLocation != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("bus"),
          position: _busLocation!,
          icon: _arrowIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          rotation: _lastBusLocation != null
              ? Geolocator.bearingBetween(
            _lastBusLocation!.latitude,
            _lastBusLocation!.longitude,
            _busLocation!.latitude,
            _busLocation!.longitude,
          )
              : 0,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    } else if (!_trackBus && _studentLocation != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("student"),
          position: _studentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    // Add Destination Marker
    if (_destination != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("destination"),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    setState(() {
      _markers = updatedMarkers;
    });

    // Move camera to latest location
    if (_controller.isCompleted) {
      _controller.future.then((controller) {
        LatLng target = _trackBus ? _busLocation ?? _studentLocation! : _studentLocation!;
        controller.animateCamera(CameraUpdate.newLatLng(target));
      });
    }

  }


  /// Builds the horizontal station timeline, highlighting the next stop
  Widget _buildStationTimeline() {
    if (_stations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No stations available'),
      );
    }

    int nextStationIndex = -1;
    if (_busLocation != null) {
      double minDistance = double.infinity;
      for (int i = 0; i < _stations.length; i++) {
        final s = _stations[i];
        double d = Geolocator.distanceBetween(
          _busLocation!.latitude,
          _busLocation!.longitude,
          s['latitude'],
          s['longitude'],
        );
        if (d < minDistance) {
          minDistance = d;
          nextStationIndex = i;
        }
      }
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _stations.length,
        itemBuilder: (context, index) {
          final station = _stations[index];
          final bool isNext = index == nextStationIndex;
          final bool isReached = _busLocation != null && index < nextStationIndex;

          return Row(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isNext
                          ? Colors.orange
                          : (isReached ? Colors.blue : Colors.grey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    station['name'],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (index != _stations.length - 1)
                Container(
                  width: 40,
                  height: 2,
                  color: index < nextStationIndex ? Colors.blue : Colors.grey,
                ),
            ],
          );
        },
      ),
    );
  }


  /// Wraps the timeline in a Card
  Widget _buildStationTimelineCard() {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: _buildStationTimeline(),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bus Tracking"), backgroundColor: Colors.blue),
      body: Column(
        children: [
          _buildStationTimelineCard(),  // ✅ Add this above everything for station timeline
          Text(_trackBus ? "Tracking Bus (🚌 → 🎯)" : "Tracking Student (🧑‍🎓 → 🚌)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(_etaMessage, style: TextStyle(fontSize: 16)),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 15),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (controller) {
                _controller.complete(controller);
                _mapController = controller;
              },
            ),
          ),


        ],
      ),
    );
  }
}