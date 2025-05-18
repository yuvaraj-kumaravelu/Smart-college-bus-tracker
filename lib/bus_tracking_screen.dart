import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:url_launcher/url_launcher.dart';

class BusTrackingScreen extends StatefulWidget {
  final String busId;

  const BusTrackingScreen({super.key, required this.busId});

  @override
  State<BusTrackingScreen> createState() => _BusTrackingScreenState();
}

class _BusTrackingScreenState extends State<BusTrackingScreen> {
  late GoogleMapController _mapController;
  final Completer<GoogleMapController> _controller = Completer();
  late DatabaseReference _dbRef;
  StreamSubscription<Position>? _locationSubscription;

  LatLng? _busLocation;
  LatLng? _destination;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String _speedMessage = "Speed: 0 km/h";
  bool _isTripStarted = false;
  bool _isRouteVisible = false;

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instance.ref("buses/${widget.busId}");
    _fetchDestinationFromFirebase();
    _initializeLocation();
  }

  Future<bool> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  void _openGoogleMaps() async {
    if (_busLocation != null && _destination != null) {
      final url =
          "https://www.google.com/maps/dir/?api=1&origin=${_busLocation!.latitude},${_busLocation!.longitude}&destination=${_destination!.latitude},${_destination!.longitude}&travelmode=driving";
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        print("❌ Could not launch Google Maps");
      }
    }
  }

  void _toggleTrip() {
    if (_isTripStarted) {
      _stopTrip();
    } else {
      _startTrip();
    }
    setState(() {
      _isTripStarted = !_isTripStarted;
    });
  }

  void _startTrip() {
    _initializeLocation();
    _dbRef.update({"status": "Active"});
    _getRoute();
    _updateMap();
  }

  void _stopTrip() {
    _locationSubscription?.cancel();
    _dbRef.update({
      "status": "Inactive",
      "latitude": null,
      "longitude": null,
    });

    setState(() {
      _markers.clear();
      _polylines.clear();
      _speedMessage = "Speed: 0 km/h";
    });

    _updateMap();
  }

  Future<void> _initializeLocation() async {
    bool hasPermission = await _checkLocationPermission();
    if (!hasPermission) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _busLocation = LatLng(position.latitude, position.longitude);
    });

    _updateBusLocationInFirebase(position.latitude, position.longitude);
    _updateMap();
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      setState(() {
        _busLocation = LatLng(position.latitude, position.longitude);
        _speedMessage = "Speed: ${position.speed.toStringAsFixed(1)} km/h";
      });

      _updateBusLocationInFirebase(position.latitude, position.longitude);
      _updateMap();
    });
  }

  void _toggleRouteVisibility() {
    if (_isRouteVisible) {
      setState(() {
        _polylines.clear();
      });
    } else {
      _getRoute();
    }
    setState(() {
      _isRouteVisible = !_isRouteVisible;
    });
  }

  Future<void> _getRoute() async {
    if (_busLocation == null || _destination == null) return;

    final String url =
        "https://router.project-osrm.org/route/v1/driving/${_busLocation!.longitude},${_busLocation!.latitude};${_destination!.longitude},${_destination!.latitude}?overview=full&geometries=polyline";

    try {
      final response = await http.get(Uri.parse(url));
      final data = jsonDecode(response.body);

      if (data['routes'] != null && data['routes'].isNotEmpty) {
        final route = data['routes'][0];

        if (route.containsKey('geometry')) {
          List<LatLng> polylineCoordinates = PolylinePoints().decodePolyline(route['geometry']).map((e) => LatLng(e.latitude,e.longitude)).toList();
          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId("route"),
                color: Colors.blue,
                width: 5,
                points: polylineCoordinates,
              ),
            };
          });
        }
      }
      _updateMap();
    } catch (e) {
      print("❌ Error fetching route: $e");
    }
  }

  void _updateBusLocationInFirebase(double lat, double lng) {
    _dbRef.update({
      "latitude": lat,
      "longitude": lng,
      "timestamp": ServerValue.timestamp,
    }).catchError((e) => print("❌ Firebase update error: $e"));
  }

  void _fetchDestinationFromFirebase() {
    _dbRef.child("destination").once().then((event) {
      final data = event.snapshot.value;
      if (data != null && data is Map && data.containsKey("latitude") && data.containsKey("longitude")) {
        setState(() {
          _destination = LatLng(data["latitude"], data["longitude"]);
        });
        _updateMap();
      }
    }).catchError((e) => print("❌ Error fetching destination: $e"));
  }

  void _updateMap() {
    setState(() {
       Set<Marker> newMarkers = {};
      if (_busLocation != null) {
        newMarkers.add(
          Marker(
            markerId: const MarkerId("bus"),
            position: _busLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
        );
      }
      if (_destination != null) {
        newMarkers.add(
          Marker(
            markerId: const MarkerId("destination"),
            position: _destination!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      }
      _markers = newMarkers;
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Driver: ${widget.busId}")),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
            CameraPosition(target: LatLng(12.9606, 77.5806), zoom: 15),
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) => _controller.complete(controller),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _speedMessage,
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton.small(
                  onPressed: _toggleTrip,
                  backgroundColor: _isTripStarted ? Colors.red : Colors.green,
                  child: Icon(_isTripStarted ? Icons.stop : Icons.play_arrow),
                ),
                SizedBox(height: 10),
                FloatingActionButton.small(
                  onPressed: _toggleRouteVisibility,
                  child: Icon(Icons.route),
                ),
                SizedBox(height: 10),
                FloatingActionButton.small(
                  onPressed: _openGoogleMaps,
                  child: Icon(Icons.map),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}