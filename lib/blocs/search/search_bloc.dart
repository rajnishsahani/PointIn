import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/building.dart';
import '../../services/building_service.dart';

// ── EVENTS ──

abstract class SearchEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class SearchQueryChanged extends SearchEvent {
  final String query;
  SearchQueryChanged(this.query);
  @override
  List<Object?> get props => [query];
}

class ClearSearch extends SearchEvent {}

// ── STATES ──

abstract class SearchState extends Equatable {
  @override
  List<Object?> get props => [];
}

class SearchInitial extends SearchState {}

class SearchResults extends SearchState {
  final List<Building> buildings;
  final List<Faculty> faculty;
  final String query;

  SearchResults({
    required this.buildings,
    required this.faculty,
    required this.query,
  });

  @override
  List<Object?> get props => [buildings, faculty, query];
}

class SearchEmpty extends SearchState {
  final String query;
  SearchEmpty(this.query);
  @override
  List<Object?> get props => [query];
}

// ── BLOC ──

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final BuildingService buildingService;

  SearchBloc({required this.buildingService}) : super(SearchInitial()) {
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<ClearSearch>(_onClearSearch);
  }

  Future<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query.trim().toLowerCase();
    if (query.isEmpty) {
      emit(SearchInitial());
      return;
    }

    final buildings = await buildingService.searchBuildings(query);
    final faculty = await buildingService.searchFaculty(query);

    if (buildings.isEmpty && faculty.isEmpty) {
      emit(SearchEmpty(event.query));
    } else {
      emit(
        SearchResults(
          buildings: buildings,
          faculty: faculty,
          query: event.query,
        ),
      );
    }
  }

  void _onClearSearch(ClearSearch event, Emitter<SearchState> emit) {
    emit(SearchInitial());
  }
}
