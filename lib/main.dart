import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'blocs/building/building_bloc.dart';
import 'blocs/search/search_bloc.dart';
import 'services/building_service.dart';
import 'views/screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const PointInApp());
}

class PointInApp extends StatelessWidget {
  const PointInApp({super.key});

  @override
  Widget build(BuildContext context) {
    final buildingService = BuildingService();

    return MultiBlocProvider(
      providers: [
        BlocProvider<BuildingBloc>(
          create:
              (_) =>
                  BuildingBloc(buildingService: buildingService)
                    ..add(LoadBuildings()),
        ),
        BlocProvider<SearchBloc>(
          create: (_) => SearchBloc(buildingService: buildingService),
        ),
      ],
      child: MaterialApp(
        title: 'PointIn',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
