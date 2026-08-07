import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../repository/device_repository.dart';

// ─── Events ─────────────────────────────────────────────
abstract class DeviceEvent extends Equatable {
  const DeviceEvent();
  @override
  List<Object?> get props => [];
}

class DevicesLoadRequested extends DeviceEvent {
  const DevicesLoadRequested();
}

class DeviceRegisterRequested extends DeviceEvent {
  final String name;
  final String deviceType;
  final String os;
  final String osVersion;

  const DeviceRegisterRequested({
    required this.name,
    required this.deviceType,
    required this.os,
    required this.osVersion,
  });

  @override
  List<Object?> get props => [name, deviceType, os, osVersion];
}

class DeviceRemoveRequested extends DeviceEvent {
  final String deviceId;
  const DeviceRemoveRequested(this.deviceId);
  @override
  List<Object?> get props => [deviceId];
}

// ─── States ─────────────────────────────────────────────
abstract class DeviceState extends Equatable {
  const DeviceState();
  @override
  List<Object?> get props => [];
}

class DeviceInitial extends DeviceState {
  const DeviceInitial();
}

class DeviceLoading extends DeviceState {
  const DeviceLoading();
}

class DeviceLoaded extends DeviceState {
  final List<Map<String, dynamic>> devices;
  final int total;
  const DeviceLoaded({required this.devices, required this.total});
  @override
  List<Object?> get props => [devices, total];
}

class DeviceError extends DeviceState {
  final String message;
  const DeviceError(this.message);
  @override
  List<Object?> get props => [message];
}

class DeviceActionSuccess extends DeviceState {
  final String message;
  const DeviceActionSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── BLoC ───────────────────────────────────────────────
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final DeviceRepository deviceRepository;

  DeviceBloc({required this.deviceRepository}) : super(const DeviceInitial()) {
    on<DevicesLoadRequested>(_onLoadRequested);
    on<DeviceRegisterRequested>(_onRegisterRequested);
    on<DeviceRemoveRequested>(_onRemoveRequested);
  }

  Future<void> _onLoadRequested(
      DevicesLoadRequested event, Emitter<DeviceState> emit) async {
    emit(const DeviceLoading());
    try {
      final result = await deviceRepository.listDevices();
      emit(DeviceLoaded(
        devices: List<Map<String, dynamic>>.from(result['devices']),
        total: result['total'],
      ));
    } catch (e) {
      emit(DeviceError(ApiClient.formatError(e)));
    }
  }

  Future<void> _onRegisterRequested(
      DeviceRegisterRequested event, Emitter<DeviceState> emit) async {
    emit(const DeviceLoading());
    try {
      await deviceRepository.registerDevice(
        name: event.name,
        deviceType: event.deviceType,
        os: event.os,
        osVersion: event.osVersion,
      );
      emit(const DeviceActionSuccess('Device registered successfully'));
      add(const DevicesLoadRequested());
    } catch (e) {
      emit(DeviceError(ApiClient.formatError(e)));
    }
  }

  Future<void> _onRemoveRequested(
      DeviceRemoveRequested event, Emitter<DeviceState> emit) async {
    try {
      await deviceRepository.removeDevice(event.deviceId);
      emit(const DeviceActionSuccess('Device removed'));
      add(const DevicesLoadRequested());
    } catch (e) {
      emit(DeviceError(ApiClient.formatError(e)));
    }
  }
}
