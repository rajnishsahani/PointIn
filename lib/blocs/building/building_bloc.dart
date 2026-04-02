import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/building.dart';
import '../../services/building_service.dart';

// ── EVENTS ── (what the user did)

abstract class BuildingEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadBuildings extends BuildingEvent {}

class SelectBuilding extends BuildingEvent {
  final String buildingId;
  SelectBuilding(this.buildingId);
  @override
  List<Object?> get props => [buildingId];
}

class FilterByType extends BuildingEvent {
  final BuildingType? type;
  FilterByType(this.type);
  @override
  List<Object?> get props => [type];
}

// ── STATES ── (what the UI shows)

abstract class BuildingState extends Equatable {
  @override
  List<Object?> get props => [];
}

class BuildingInitial extends BuildingState {}

class BuildingLoading extends BuildingState {}

class BuildingsLoaded extends BuildingState {
  final List<Building> buildings;
  final List<Building> filteredBuildings;
  final BuildingType? activeFilter;

  BuildingsLoaded({
    required this.buildings,
    required this.filteredBuildings,
    this.activeFilter,
  });

  @override
  List<Object?> get props => [buildings, filteredBuildings, activeFilter];
}

class BuildingDetailLoaded extends BuildingState {
  final Building building;
  BuildingDetailLoaded({required this.building});
  @override
  List<Object?> get props => [building];
}

class BuildingError extends BuildingState {
  final String message;
  BuildingError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── BLOC ── (connects events to states)

class BuildingBloc extends Bloc<BuildingEvent, BuildingState> {
  final BuildingService buildingService;
  List<Building> _allBuildings = [];

  BuildingBloc({required this.buildingService}) : super(BuildingInitial()) {
    on<LoadBuildings>(_onLoadBuildings);
    on<SelectBuilding>(_onSelectBuilding);
    on<FilterByType>(_onFilterByType);
  }

  Future<void> _onLoadBuildings(
    LoadBuildings event,
    Emitter<BuildingState> emit,
  ) async {
    emit(BuildingLoading());
    try {
      _allBuildings = await buildingService.getAllBuildings();
      emit(
        BuildingsLoaded(
          buildings: _allBuildings,
          filteredBuildings: _allBuildings,
        ),
      );
    } catch (e) {
      emit(BuildingError(e.toString()));
    }
  }

  Future<void> _onSelectBuilding(
    SelectBuilding event,
    Emitter<BuildingState> emit,
  ) async {
    final building = await buildingService.getBuildingById(event.buildingId);
    if (building != null) {
      emit(BuildingDetailLoaded(building: building));
    }
  }

  void _onFilterByType(FilterByType event, Emitter<BuildingState> emit) {
    if (event.type == null) {
      emit(
        BuildingsLoaded(
          buildings: _allBuildings,
          filteredBuildings: _allBuildings,
        ),
      );
    } else {
      final filtered = _allBuildings
          .where((b) => b.type == event.type)
          .toList();
      emit(
        BuildingsLoaded(
          buildings: _allBuildings,
          filteredBuildings: filtered,
          activeFilter: event.type,
        ),
      );
    }
  }
}
