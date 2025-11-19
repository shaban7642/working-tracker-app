import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop
  if (Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(
        300,
        300,
      ), // Increased to accommodate expanded dropdown
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: true,
    );

    windowManager.waitUntilReadyToShow(
      windowOptions,
      () async {
        // Position the widget on the right side of the screen
        await windowManager.setPosition(
          const Offset(1200, 300),
        );
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setAsFrameless();
        await windowManager.setAlwaysOnTop(true);

        // Make the window transparent
        await windowManager.setOpacity(1.0);
        await windowManager.setBackgroundColor(
          Colors.transparent,
        );
      },
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Floating Widget',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isHovered = false;
  bool _isExpanded =
      false; // Track inline dropdown expansion

  // Project timer management
  Map<String, Duration> projectTimers = {};
  String currentProject = "Select Project";
  Timer? activeTimer;
  Duration currentDuration = Duration.zero;

  // Available projects
  final List<String> availableProjects = [
    "Binghatti Project_1",
    "Binghatti Project_2",
    "Binghatti Project_3",
    "Marina Heights",
    "Downtown Tower",
    "Beach Resort",
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation =
        Tween<double>(
          begin: 0.2, // 80% hidden
          end: 1.0, // Fully visible
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeInOut,
          ),
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    activeTimer?.cancel();
    super.dispose();
  }

  void _selectProject(String projectName) {
    setState(() {
      // Save current project's timer
      if (currentProject != "Select Project") {
        projectTimers[currentProject] = currentDuration;
      }

      // Cancel existing timer
      activeTimer?.cancel();

      // Update current project
      currentProject = projectName;

      // Load or initialize the project's timer
      currentDuration =
          projectTimers[projectName] ?? Duration.zero;

      // Start the timer for the new project
      activeTimer = Timer.periodic(
        const Duration(seconds: 1),
        (timer) {
          setState(() {
            currentDuration =
                currentDuration +
                const Duration(seconds: 1);
            projectTimers[currentProject] = currentDuration;
          });
        },
      );

      // Close the dropdown after selection
      _isExpanded = false;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(
      duration.inMinutes.remainder(60),
    );
    String seconds = twoDigits(
      duration.inSeconds.remainder(60),
    );
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final slideValue = _animation.value;
          final xOffset =
              (1 - slideValue) * 240; // Slide amount

          return Stack(
            children: [
              // Main widget container with MouseRegion
              Positioned(
                right: -xOffset,
                top: 0,
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      _isHovered = true;
                    });
                    _controller.forward();
                  },
                  onExit: (_) {
                    // Don't collapse if dropdown is expanded
                    if (!_isExpanded) {
                      setState(() {
                        _isHovered = false;
                      });
                      _controller.reverse();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(
                      milliseconds: 300,
                    ),
                    curve: Curves.easeInOut,
                    width: 280,
                    height: _isExpanded
                        ? 72.0 +
                              math.min(
                                220,
                                availableProjects.length *
                                    55.0,
                              )
                        : 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.15,
                          ),
                          spreadRadius: 0,
                          blurRadius: 10,
                          offset: const Offset(-2, 2),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.grey.withValues(
                          alpha: 0.2,
                        ),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          children: [
                            // Main Row Section
                            Container(
                              height: 70,
                              padding:
                                  const EdgeInsets.symmetric(
                                    horizontal: 12.0,
                                    vertical: 8.0,
                                  ),
                              child: Row(
                                children: [
                                  // Building GIF with fallback
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Image.asset(
                                      'assets/blueprint.gif',
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) {
                                        // Fallback to icon if GIF not found
                                        return Icon(
                                          Icons.apartment,
                                          color: Colors.brown[400],
                                          size: 28,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Project Name and Timer
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment
                                              .center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .center,
                                      children: [
                                        // Project Name
                                        Text(
                                          currentProject,
                                          style: TextStyle(
                                            color:
                                                currentProject ==
                                                    "Select Project"
                                                ? Colors
                                                      .grey[600]
                                                : Colors
                                                      .black87,
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight
                                                    .w500,
                                          ),
                                          overflow:
                                              TextOverflow
                                                  .ellipsis,
                                        ),
                                        const SizedBox(
                                          height: 2,
                                        ),
                                        // Timer Display
                                        Text(
                                          _formatDuration(
                                            currentDuration,
                                          ),
                                          style: TextStyle(
                                            color: Colors
                                                .grey[700],
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                            fontFamily:
                                                'monospace',
                                            letterSpacing:
                                                1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Dropdown Arrow with rotation
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isExpanded =
                                            !_isExpanded;
                                      });
                                    },
                                    child: AnimatedRotation(
                                      turns: _isExpanded
                                          ? 0.5
                                          : 0,
                                      duration:
                                          const Duration(
                                            milliseconds:
                                                300,
                                          ),
                                      child: Icon(
                                        Icons
                                            .arrow_drop_down,
                                        color: Colors
                                            .grey[700],
                                        size: 28,
                                      ),
                                    ),
                                  ),

                                  // Close button
                                  InkWell(
                                    onTap: () {
                                      exit(0);
                                    },
                                    child: Container(
                                      padding:
                                          const EdgeInsets.all(
                                            4,
                                          ),
                                      child: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors
                                            .grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Expandable Project List
                            if (_isExpanded)
                              Container(
                                height: math.min(
                                  220,
                                  availableProjects.length *
                                      55.0,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.grey
                                          .withValues(
                                            alpha: 0.2,
                                          ),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount:
                                      availableProjects
                                          .length,
                                  itemBuilder: (context, index) {
                                    final project =
                                        availableProjects[index];
                                    final isActive =
                                        project ==
                                        currentProject;
                                    final projectDuration =
                                        projectTimers[project] ??
                                        Duration.zero;

                                    return InkWell(
                                      onTap: () =>
                                          _selectProject(
                                            project,
                                          ),
                                      child: Container(
                                        height: 55,
                                        padding:
                                            const EdgeInsets.symmetric(
                                              horizontal:
                                                  12,
                                              vertical: 8,
                                            ),
                                        child: Row(
                                          children: [
                                            // Project icon
                                            Icon(
                                              Icons
                                                  .apartment,
                                              size: 20,
                                              color:
                                                  isActive
                                                  ? Colors
                                                        .blue[600]
                                                  : Colors
                                                        .grey[600],
                                            ),
                                            const SizedBox(
                                              width: 10,
                                            ),
                                            // Project name
                                            Expanded(
                                              child: Text(
                                                project,
                                                style: TextStyle(
                                                  color:
                                                      isActive
                                                      ? Colors.blue[600]
                                                      : Colors.black87,
                                                  fontWeight:
                                                      isActive
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            // Timer for this project
                                            if (projectDuration
                                                    .inSeconds >
                                                0)
                                              Text(
                                                _formatDuration(
                                                  projectDuration,
                                                ),
                                                style: TextStyle(
                                                  color: Colors
                                                      .grey[600],
                                                  fontSize:
                                                      12,
                                                  fontFamily:
                                                      'monospace',
                                                ),
                                              ),
                                            // Active indicator
                                            if (isActive)
                                              Container(
                                                margin:
                                                    const EdgeInsets.only(
                                                      left:
                                                          8,
                                                    ),
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Colors
                                                      .green,
                                                  shape: BoxShape
                                                      .circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
