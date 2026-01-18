import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;
import '../app/theme/app_theme.dart';
import '../widgets/global/global_logo_bar.dart';
import '../telegram_safe_area.dart';
import 'home_page.dart';
import 'trade_page.dart';
import 'wallets_page.dart';

class SimpleMainPage extends StatefulWidget {
  const SimpleMainPage({super.key});

  @override
  State<SimpleMainPage> createState() => _SimpleMainPageState();
}

class _SimpleMainPageState extends State<SimpleMainPage>
    with TickerProviderStateMixin {
  // Helper method to calculate adaptive bottom padding
  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();

    // Formula: bottom SafeAreaInset + 30px
    final bottomPadding = safeAreaInset.bottom + 30;
    return bottomPadding;
  }

  // Helper method to calculate GlobalBottomBar height
  double _getGlobalBottomBarHeight() {
    // Minimum height: container padding (10 + 15) + TextField minHeight (30)
    return 10.0 + 30.0 + 15.0;
  }

  String _selectedTab = 'Feed'; // Default selected tab

  // Mock coin data
  final List<Map<String, dynamic>> _coins = [
    {
      'icon': 'assets/sample/DLLR.svg',
      'ticker': 'DLLR',
      'blockchain': 'TON',
      'amount': '1',
      'usdValue': '\$1',
    },
  ];

  // Feed items data with SVG images
  List<Map<String, dynamic>> get _feedItems {
    
    return [
      {
        'icon': 'assets/sample/mak/3.svg',
        'primaryText': 'Robat',
        'secondaryText': "Welcome! I’ve created a wallet for you.",
        'timestamp': '7:55',
        'rightText': null,
      },
      {
        'icon': r'assets/sample/mak/+1$.svg',
        'primaryText': 'Incoming task',
        'secondaryText': 'Send link with \$1 and get +\$1',
        'timestamp': '17:11',
        'rightText': 'N/A',
      },
      {
        'icon': 'assets/sample/mak/1.svg',
        'primaryText': 'CLATH 41 NFT recieved',
        'secondaryText': 'AI CLATH Collection',
        'timestamp': '15:22',
        'rightText': 'N/A',
      },
      {
        'icon': 'assets/sample/DLLR.svg',
        'primaryText': 'Token granted',
        'secondaryText': '\$1',
        'timestamp': '13:17',
        'rightText': '+1 DLLR',
      },
    ];
  }

  // Tasks items data with SVG images
  List<Map<String, dynamic>> get _tasksItems {
    return [
      {
        'icon': r'assets/sample/mak/+1$.svg',
        'primaryText': 'Incoming task',
        'secondaryText': 'Send link with \$1 and get +\$1',
        'timestamp': '17:11',
        'rightText': 'N/A',
      },
    ];
  }

  // Chat items data with SVG images
  List<Map<String, dynamic>> get _chatItems {
    return [
      {
        'icon': 'assets/sample/mak/3.svg',
        'primaryText': 'Robat',
        'secondaryText': "Welcome! I've created a wallet for you.",
        'timestamp': '7:55',
        'rightText': null,
      },
    ];
  }

  // Items data for Items tab grid
  List<Map<String, dynamic>> get _items {
    return [
      {
        'icon': 'assets/sample/item.svg',
        'title': 'CLATH 41',
        'subtitle': 'AI CLATH',
      },
    ];
  }

  late final AnimationController _bgController;
  late final Animation<double> _bgAnimation;
  late final double _bgSeed;
  late final AnimationController _noiseController;
  late final Animation<double> _noiseAnimation;
  
  // Scroll controller for main content
  final ScrollController _mainScrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();

    final random = math.Random();
    final durationMs = 20000 + random.nextInt(14000);
    _bgController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    )..repeat(reverse: true);
    _bgAnimation =
        CurvedAnimation(parent: _bgController, curve: Curves.easeInOut);
    _bgSeed = random.nextDouble();
    _noiseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat(reverse: true);
    _noiseAnimation =
        Tween<double>(begin: -0.2, end: 0.2).animate(CurvedAnimation(
      parent: _noiseController,
      curve: Curves.easeInOut,
    ));
    
    // Listen to scroll changes to update scroll indicator
    _mainScrollController.addListener(_updateScrollIndicator);
    
    // Calculate initial scroll indicator state after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicator();
    });
  }

  // Update scroll indicator state
  void _updateScrollIndicator() {
    if (_mainScrollController.hasClients) {
      // Trigger rebuild for scroll indicator (LayoutBuilder will recalculate)
      setState(() {
        // LayoutBuilder calculates values directly from ScrollController
      });
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _noiseController.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  Color _shiftColor(Color base, double shift) {
    final hsl = HSLColor.fromColor(base);
    final newLightness = (hsl.lightness + shift).clamp(0.0, 1.0);
    final newHue = (hsl.hue + shift * 10) % 360;
    final newSaturation = (hsl.saturation + shift * 0.1).clamp(0.0, 1.0);
    return hsl
        .withLightness(newLightness)
        .withHue(newHue)
        .withSaturation(newSaturation)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _bgAnimation,
        builder: (context, child) {
          final baseShimmer =
              math.sin(2 * math.pi * (_bgAnimation.value + _bgSeed));
          final shimmer = 0.007 * baseShimmer;
          final baseColors = AppTheme.baseColors;
          const stopsCount = 28;
          final colors = List.generate(stopsCount, (index) {
            final progress = index / (stopsCount - 1);
            final scaled = progress * (baseColors.length - 1);
            final lowerIndex = scaled.floor();
            final upperIndex = scaled.ceil();
            final frac = scaled - lowerIndex;
            final lower =
                baseColors[lowerIndex.clamp(0, baseColors.length - 1)];
            final upper =
                baseColors[upperIndex.clamp(0, baseColors.length - 1)];
            final blended = Color.lerp(lower, upper, frac)!;
            final offset = index * 0.0015;
            return _shiftColor(blended, shimmer * (0.035 + offset));
          });
          final stops = List.generate(
              colors.length, (index) => index / (colors.length - 1));
          final rotation =
              math.sin(2 * math.pi * (_bgAnimation.value + _bgSeed)) * 0.35;
          final begin = Alignment(-0.8 + rotation, -0.7 - rotation * 0.2);
          final end = Alignment(0.9 - rotation, 0.8 + rotation * 0.2);
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: colors,
                    stops: stops,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _noiseAnimation,
                builder: (context, _) {
                  final alignment = Alignment(
                    0.2 + _noiseAnimation.value,
                    -0.4 + _noiseAnimation.value * 0.5,
                  );
                  return Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: alignment,
                        radius: 0.75,
                        colors: [
                          Colors.white.withValues(alpha: 0.01),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  );
                },
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.7, -0.6),
                    radius: 0.8,
                    colors: [
                      _shiftColor(AppTheme.radialGradientColor, shimmer * 0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                  color: AppTheme.overlayColor.withValues(alpha: 0.02),
                ),
              ),
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.01),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.005),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: SafeArea(
          bottom: false,
          top: false, // Disable SafeArea top padding - we handle it manually
          child: ValueListenableBuilder<bool>(
            valueListenable: GlobalLogoBar.fullscreenNotifier,
            builder: (context, isFullscreen, child) {
              final topPadding = GlobalLogoBar.getContentTopPadding();
              final logoBlockHeight = GlobalLogoBar.getLogoBlockHeight();
              final bottomBarHeight = _getGlobalBottomBarHeight();
              print('[SimpleMainPage] Applying content top padding: $topPadding');
              return Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: _getAdaptiveBottomPadding(),
                        top: topPadding, // Dynamic padding based on logo visibility
                        left: 15,
                        right: 15),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 570),
                        child: SingleChildScrollView(
                          controller: _mainScrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Hash row with icons - content part
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            '..xk5str4e',
                            style: TextStyle(
                              fontFamily: 'Aeroport Mono',
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF818181),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  // Copy action
                                },
                                child: SvgPicture.asset(
                                  'assets/icons/copy.svg',
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              const SizedBox(width: 15),
                              GestureDetector(
                                onTap: () {
                                  // Edit action
                                },
                                child: SvgPicture.asset(
                                  'assets/icons/edit.svg',
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              const SizedBox(width: 15),
                              GestureDetector(
                                onTap: () {
                                  // Edit action
                                },
                                child: SvgPicture.asset(
                                  'assets/icons/key.svg',
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              const SizedBox(width: 15),
                              GestureDetector(
                                onTap: () {
                                  // Exit action
                                },
                                child: SvgPicture.asset(
                                  'assets/icons/exit.svg',
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                r'$1',
                                style: TextStyle(
                                  fontFamily: 'Aeroport',
                                  fontSize: 30,
                                  fontWeight: FontWeight.w400,
                                  color: AppTheme.textColor,
                                  height: 1.0,
                                ),
                                textHeightBehavior: const TextHeightBehavior(
                                  applyHeightToFirstAscent: false,
                                  applyHeightToLastDescent: false,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (context, animation, secondaryAnimation) => const WalletsPage(),
                                      transitionDuration: Duration.zero,
                                      reverseTransitionDuration: Duration.zero,
                                    ),
                                  );
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Sendal Rodriges',
                                      style: TextStyle(
                                        fontFamily: 'Aeroport',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF818181),
                                        height: 1.0,
                                      ),
                                      textHeightBehavior:
                                          TextHeightBehavior(
                                        applyHeightToFirstAscent: false,
                                        applyHeightToLastDescent: false,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    SvgPicture.asset('assets/icons/select.svg', width: 5, height: 10),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset(
                                      AppTheme.isLightTheme
                                          ? 'assets/icons/menudva/get_light.svg'
                                          : 'assets/icons/menudva/get_dark.svg',
                                      width: 30,
                                      height: 30,
                                    ),
                                    const SizedBox(height: 5),
                                    SizedBox(
                                      height: 15,
                                      child: Center(
                                        child: Text(
                                          'Get',
                                          style: TextStyle(
                                            fontFamily: 'Aeroport',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: AppTheme.textColor,
                                            height: 1.0,
                                          ),
                                          textHeightBehavior:
                                              const TextHeightBehavior(
                                            applyHeightToFirstAscent: false,
                                            applyHeightToLastDescent: false,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) => const HomePage(),
                                        transitionDuration: Duration.zero,
                                        reverseTransitionDuration: Duration.zero,
                                      ),
                                    );
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SvgPicture.asset(
                                        AppTheme.isLightTheme
                                            ? 'assets/icons/menudva/swap_light.svg'
                                            : 'assets/icons/menudva/swap_dark.svg',
                                        width: 30,
                                        height: 30,
                                      ),
                                      const SizedBox(height: 5),
                                      SizedBox(
                                        height: 15,
                                        child: Center(
                                          child: Text(
                                            'Swap',
                                            style: TextStyle(
                                              fontFamily: 'Aeroport',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textColor,
                                              height: 1.0,
                                            ),
                                            textHeightBehavior:
                                                const TextHeightBehavior(
                                              applyHeightToFirstAscent: false,
                                              applyHeightToLastDescent: false,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset(
                                      AppTheme.isLightTheme
                                          ? 'assets/icons/menudva/earn_light.svg'
                                          : 'assets/icons/menudva/earn_dark.svg',
                                      width: 30,
                                      height: 30,
                                    ),
                                    const SizedBox(height: 5),
                                    SizedBox(
                                      height: 15,
                                      child: Center(
                                        child: Text(
                                          'Apps',
                                          style: TextStyle(
                                            fontFamily: 'Aeroport',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: AppTheme.textColor,
                                            height: 1.0,
                                          ),
                                          textHeightBehavior:
                                              const TextHeightBehavior(
                                            applyHeightToFirstAscent: false,
                                            applyHeightToLastDescent: false,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) => const TradePage(),
                                        transitionDuration: Duration.zero,
                                        reverseTransitionDuration: Duration.zero,
                                      ),
                                    );
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SvgPicture.asset(
                                        AppTheme.isLightTheme
                                            ? 'assets/icons/menudva/trade_light.svg'
                                            : 'assets/icons/menudva/trade_dark.svg',
                                        width: 30,
                                        height: 30,
                                      ),
                                      const SizedBox(height: 5),
                                      SizedBox(
                                        height: 15,
                                        child: Center(
                                          child: Text(
                                            'Trade',
                                            style: TextStyle(
                                              fontFamily: 'Aeroport',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textColor,
                                              height: 1.0,
                                            ),
                                            textHeightBehavior:
                                                const TextHeightBehavior(
                                              applyHeightToFirstAscent: false,
                                              applyHeightToLastDescent: false,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset(
                                      AppTheme.isLightTheme
                                          ? 'assets/icons/menudva/send_light.svg'
                                          : 'assets/icons/menudva/send_dark.svg',
                                      width: 30,
                                      height: 30,
                                    ),
                                    const SizedBox(height: 5),
                                    SizedBox(
                                      height: 15,
                                      child: Center(
                                        child: Text(
                                          'Send',
                                          style: TextStyle(
                                            fontFamily: 'Aeroport',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: AppTheme.textColor,
                                            height: 1.0,
                                          ),
                                          textHeightBehavior:
                                              const TextHeightBehavior(
                                            applyHeightToFirstAscent: false,
                                            applyHeightToLastDescent: false,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 'Feed';
                                  });
                                },
                                child: Text(
                                  'Feed',
                                  style: TextStyle(
                                    fontFamily: 'Aeroport',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedTab == 'Feed'
                                        ? AppTheme.textColor
                                        : const Color(0xFF818181),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 'Chat';
                                  });
                                },
                                child: Text(
                                  'Chat',
                                  style: TextStyle(
                                    fontFamily: 'Aeroport',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedTab == 'Chat'
                                        ? AppTheme.textColor
                                        : const Color(0xFF818181),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 'Tasks';
                                  });
                                },
                                child: Text(
                                  'Tasks',
                                  style: TextStyle(
                                    fontFamily: 'Aeroport',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedTab == 'Tasks'
                                        ? AppTheme.textColor
                                        : const Color(0xFF818181),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 'Items';
                                  });
                                },
                                child: Text(
                                  'Items',
                                  style: TextStyle(
                                    fontFamily: 'Aeroport',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedTab == 'Items'
                                        ? AppTheme.textColor
                                        : const Color(0xFF818181),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 'Coins';
                                  });
                                },
                                child: Text(
                                  'Coins',
                                  style: TextStyle(
                                    fontFamily: 'Aeroport',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedTab == 'Coins'
                                        ? AppTheme.textColor
                                        : const Color(0xFF818181),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Feed list - shown when Feed tab is selected
                          if (_selectedTab == 'Feed')
                            Column(
                              children: _feedItems.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Feed item icon - 30px, centered vertically relative to 40px text columns
                                        SvgPicture.asset(
                                          item['icon'] as String,
                                          width: 30,
                                          height: 30,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 10),
                                        // Primary and secondary text column
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    item['primaryText'] as String,
                                                    style: TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: AppTheme.textColor,
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    item['secondaryText'] as String,
                                                    style: const TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      color: Color(0xFF818181),
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Timestamp and right text column (right-aligned)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            SizedBox(
                                              height: 20,
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  item['timestamp'] as String,
                                                  style: TextStyle(
                                                    fontFamily: 'Aeroport',
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500, // medium
                                                    color: AppTheme.textColor,
                                                    height: 1.0,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                  textHeightBehavior:
                                                      const TextHeightBehavior(
                                                    applyHeightToFirstAscent:
                                                        false,
                                                    applyHeightToLastDescent:
                                                        false,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 20,
                                              child: item['rightText'] != null
                                                  ? Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        item['rightText'] as String,
                                                        style: const TextStyle(
                                                          fontFamily: 'Aeroport',
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w400,
                                                          color: Color(0xFF818181),
                                                          height: 1.0,
                                                        ),
                                                        textAlign: TextAlign.right,
                                                        textHeightBehavior:
                                                            const TextHeightBehavior(
                                                          applyHeightToFirstAscent:
                                                              false,
                                                          applyHeightToLastDescent:
                                                              false,
                                                        ),
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          // Chat list - shown when Chat tab is selected
                          if (_selectedTab == 'Chat')
                            Column(
                              children: _chatItems.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Chat item icon - 30px, centered vertically relative to 40px text columns
                                        SvgPicture.asset(
                                          item['icon'] as String,
                                          width: 30,
                                          height: 30,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 10),
                                        // Primary and secondary text column
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    item['primaryText'] as String,
                                                    style: TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: AppTheme.textColor,
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    item['secondaryText'] as String,
                                                    style: const TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      color: Color(0xFF818181),
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Timestamp and right text column (right-aligned)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            SizedBox(
                                              height: 20,
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  item['timestamp'] as String,
                                                  style: TextStyle(
                                                    fontFamily: 'Aeroport',
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500, // medium
                                                    color: AppTheme.textColor,
                                                    height: 1.0,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                  textHeightBehavior:
                                                      const TextHeightBehavior(
                                                    applyHeightToFirstAscent:
                                                        false,
                                                    applyHeightToLastDescent:
                                                        false,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 20,
                                              child: item['rightText'] != null
                                                  ? Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        item['rightText'] as String,
                                                        style: const TextStyle(
                                                          fontFamily: 'Aeroport',
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w400,
                                                          color: Color(0xFF818181),
                                                          height: 1.0,
                                                        ),
                                                        textAlign: TextAlign.right,
                                                        textHeightBehavior:
                                                            const TextHeightBehavior(
                                                          applyHeightToFirstAscent:
                                                              false,
                                                          applyHeightToLastDescent:
                                                              false,
                                                        ),
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          // Tasks list - shown when Tasks tab is selected
                          if (_selectedTab == 'Tasks')
                            Column(
                              children: _tasksItems.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Task item icon - 30px, centered vertically relative to 40px text columns
                                        SvgPicture.asset(
                                          item['icon'] as String,
                                          width: 30,
                                          height: 30,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 10),
                                        // Primary and secondary text column
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    item['primaryText'] as String,
                                                    style: TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: AppTheme.textColor,
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    item['secondaryText'] as String,
                                                    style: const TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      color: Color(0xFF818181),
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Timestamp and right text column (right-aligned)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            SizedBox(
                                              height: 20,
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  item['timestamp'] as String,
                                                  style: TextStyle(
                                                    fontFamily: 'Aeroport',
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500, // medium
                                                    color: AppTheme.textColor,
                                                    height: 1.0,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                  textHeightBehavior:
                                                      const TextHeightBehavior(
                                                    applyHeightToFirstAscent:
                                                        false,
                                                    applyHeightToLastDescent:
                                                        false,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 20,
                                              child: item['rightText'] != null
                                                  ? Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        item['rightText'] as String,
                                                        style: const TextStyle(
                                                          fontFamily: 'Aeroport',
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w400,
                                                          color: Color(0xFF818181),
                                                          height: 1.0,
                                                        ),
                                                        textAlign: TextAlign.right,
                                                        textHeightBehavior:
                                                            const TextHeightBehavior(
                                                          applyHeightToFirstAscent:
                                                              false,
                                                          applyHeightToLastDescent:
                                                              false,
                                                        ),
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          // Items grid - shown when Items tab is selected
                          if (_selectedTab == 'Items')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Calculate item width: (availableWidth - crossAxisSpacing) / crossAxisCount
                                  // Available width accounts for container padding (15px on each side)
                                  final availableWidth = constraints.maxWidth;
                                  final itemWidth = (availableWidth - 15.0) / 2.0;
                                  // Item height = image height (same as width since aspect ratio 1:1) + spacing + text heights
                                  // Image: itemWidth (1:1 aspect ratio)
                                  // Spacing: 15px (after image) + 5px (between texts) = 20px
                                  // Text heights: 20px (title) + 20px (subtitle) = 40px
                                  // Total: itemWidth + 15 + 20 + 5 + 20 = itemWidth + 60
                                  final itemHeight = itemWidth + 60.0;
                                  
                                  return GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 15.0,
                                      mainAxisSpacing: 20.0,
                                      mainAxisExtent: itemHeight,
                                    ),
                                    itemCount: _items.length,
                                    itemBuilder: (context, index) {
                                      final item = _items[index];
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Image - rectangle filling the width
                                          AspectRatio(
                                            aspectRatio: 1.0,
                                            child: SvgPicture.asset(
                                              item['icon'] as String,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          const SizedBox(height: 15),
                                          // Title
                                          Text(
                                            item['title'] as String,
                                            style: TextStyle(
                                              fontFamily: 'Aeroport',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w400,
                                              color: AppTheme.textColor,
                                              height: 20 / 15, // 20px line height / 15px font size
                                            ),
                                            textHeightBehavior: const TextHeightBehavior(
                                              applyHeightToFirstAscent: false,
                                              applyHeightToLastDescent: false,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 5),
                                          // Subtitle
                                          Flexible(
                                            child: Text(
                                              item['subtitle'] as String,
                                              style: const TextStyle(
                                                fontFamily: 'Aeroport',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w400,
                                                color: Color(0xFF818181),
                                                height: 20 / 15,
                                              ),
                                              textHeightBehavior: const TextHeightBehavior(
                                                applyHeightToFirstAscent: false,
                                                applyHeightToLastDescent: false,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          // Coins list - shown when Coins tab is selected
                          if (_selectedTab == 'Coins')
                            Column(
                              children: _coins.map((coin) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Coin icon - 30px, centered vertically relative to 40px text columns
                                        (coin['icon'] as String).endsWith('.svg')
                                            ? SvgPicture.asset(
                                                coin['icon'] as String,
                                                width: 30,
                                                height: 30,
                                                fit: BoxFit.contain,
                                              )
                                            : Image.asset(
                                                coin['icon'] as String,
                                                width: 30,
                                                height: 30,
                                                fit: BoxFit.contain,
                                              ),
                                        const SizedBox(width: 10),
                                        // Coin ticker and blockchain column
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    coin['ticker'] as String,
                                                    style: TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: AppTheme.textColor,
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                height: 20,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    coin['blockchain']
                                                        as String,
                                                    style: const TextStyle(
                                                      fontFamily: 'Aeroport',
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      color: Color(0xFF818181),
                                                      height: 1.0,
                                                    ),
                                                    textHeightBehavior:
                                                        const TextHeightBehavior(
                                                      applyHeightToFirstAscent:
                                                          false,
                                                      applyHeightToLastDescent:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Amount and USD value column (right-aligned)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            SizedBox(
                                              height: 20,
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  coin['amount'] as String,
                                                  style: TextStyle(
                                                    fontFamily: 'Aeroport',
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppTheme.textColor,
                                                    height: 1.0,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                  textHeightBehavior:
                                                      const TextHeightBehavior(
                                                    applyHeightToFirstAscent:
                                                        false,
                                                    applyHeightToLastDescent:
                                                        false,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 20,
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  coin['usdValue'] as String,
                                                  style: const TextStyle(
                                                    fontFamily: 'Aeroport',
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w400,
                                                    color: Color(0xFF818181),
                                                    height: 1.0,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                  textHeightBehavior:
                                                      const TextHeightBehavior(
                                                    applyHeightToFirstAscent:
                                                        false,
                                                    applyHeightToLastDescent:
                                                        false,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ],
                  ),
                ),
                      ),
                    ),
                  ),
                  // Scroll indicator - always visible, 5px from right edge
                  // Height reflects visible area dimension
                  Positioned(
                    right: 5,
                    top: logoBlockHeight,
                    bottom: bottomBarHeight,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final containerHeight = constraints.maxHeight;
                        if (containerHeight <= 0 || !_mainScrollController.hasClients) {
                          return const SizedBox.shrink();
                        }
                        
                        try {
                          final position = _mainScrollController.position;
                          final maxScroll = position.maxScrollExtent;
                          final currentScroll = position.pixels;
                          final viewportHeight = position.viewportDimension;
                          final totalHeight = viewportHeight + maxScroll;
                          
                          // If no scrolling needed, hide the indicator
                          if (maxScroll <= 0 || totalHeight <= 0) {
                            return const SizedBox.shrink();
                          }
                          
                          // Calculate indicator height based on visible area
                          final indicatorHeightRatio = (viewportHeight / totalHeight).clamp(0.0, 1.0);
                          final indicatorHeight = (containerHeight * indicatorHeightRatio)
                              .clamp(0.0, containerHeight);
                          
                          // If indicator height is 0 or very small, hide it
                          if (indicatorHeight <= 0) {
                            return const SizedBox.shrink();
                          }
                          
                          // Calculate scroll position
                          final scrollPosition = (currentScroll / maxScroll).clamp(0.0, 1.0);
                          final availableSpace = (containerHeight - indicatorHeight)
                              .clamp(0.0, containerHeight);
                          final topPosition = (scrollPosition * availableSpace)
                              .clamp(0.0, containerHeight);
                          
                          return Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: EdgeInsets.only(top: topPosition),
                              child: Container(
                                width: 1,
                                height: indicatorHeight,
                                color: const Color(0xFF818181),
                              ),
                            ),
                          );
                        } catch (e) {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

