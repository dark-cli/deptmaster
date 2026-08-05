// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ClientError {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ClientErrorCopyWith<$Res> {
  factory $ClientErrorCopyWith(
          ClientError value, $Res Function(ClientError) then) =
      _$ClientErrorCopyWithImpl<$Res, ClientError>;
}

/// @nodoc
class _$ClientErrorCopyWithImpl<$Res, $Val extends ClientError>
    implements $ClientErrorCopyWith<$Res> {
  _$ClientErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$ClientError_NetworkImplCopyWith<$Res> {
  factory _$$ClientError_NetworkImplCopyWith(_$ClientError_NetworkImpl value,
          $Res Function(_$ClientError_NetworkImpl) then) =
      __$$ClientError_NetworkImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$ClientError_NetworkImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_NetworkImpl>
    implements _$$ClientError_NetworkImplCopyWith<$Res> {
  __$$ClientError_NetworkImplCopyWithImpl(_$ClientError_NetworkImpl _value,
      $Res Function(_$ClientError_NetworkImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ClientError_NetworkImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ClientError_NetworkImpl extends ClientError_Network {
  const _$ClientError_NetworkImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'ClientError.network(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_NetworkImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientError_NetworkImplCopyWith<_$ClientError_NetworkImpl> get copyWith =>
      __$$ClientError_NetworkImplCopyWithImpl<_$ClientError_NetworkImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return network(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return network?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (network != null) {
      return network(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return network(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return network?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (network != null) {
      return network(this);
    }
    return orElse();
  }
}

abstract class ClientError_Network extends ClientError {
  const factory ClientError_Network(final String field0) =
      _$ClientError_NetworkImpl;
  const ClientError_Network._() : super._();

  String get field0;
  @JsonKey(ignore: true)
  _$$ClientError_NetworkImplCopyWith<_$ClientError_NetworkImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ClientError_AuthDeclinedImplCopyWith<$Res> {
  factory _$$ClientError_AuthDeclinedImplCopyWith(
          _$ClientError_AuthDeclinedImpl value,
          $Res Function(_$ClientError_AuthDeclinedImpl) then) =
      __$$ClientError_AuthDeclinedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$ClientError_AuthDeclinedImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_AuthDeclinedImpl>
    implements _$$ClientError_AuthDeclinedImplCopyWith<$Res> {
  __$$ClientError_AuthDeclinedImplCopyWithImpl(
      _$ClientError_AuthDeclinedImpl _value,
      $Res Function(_$ClientError_AuthDeclinedImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$ClientError_AuthDeclinedImpl extends ClientError_AuthDeclined {
  const _$ClientError_AuthDeclinedImpl() : super._();

  @override
  String toString() {
    return 'ClientError.authDeclined()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_AuthDeclinedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return authDeclined();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return authDeclined?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (authDeclined != null) {
      return authDeclined();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return authDeclined(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return authDeclined?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (authDeclined != null) {
      return authDeclined(this);
    }
    return orElse();
  }
}

abstract class ClientError_AuthDeclined extends ClientError {
  const factory ClientError_AuthDeclined() = _$ClientError_AuthDeclinedImpl;
  const ClientError_AuthDeclined._() : super._();
}

/// @nodoc
abstract class _$$ClientError_AuthExpiredImplCopyWith<$Res> {
  factory _$$ClientError_AuthExpiredImplCopyWith(
          _$ClientError_AuthExpiredImpl value,
          $Res Function(_$ClientError_AuthExpiredImpl) then) =
      __$$ClientError_AuthExpiredImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$ClientError_AuthExpiredImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_AuthExpiredImpl>
    implements _$$ClientError_AuthExpiredImplCopyWith<$Res> {
  __$$ClientError_AuthExpiredImplCopyWithImpl(
      _$ClientError_AuthExpiredImpl _value,
      $Res Function(_$ClientError_AuthExpiredImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$ClientError_AuthExpiredImpl extends ClientError_AuthExpired {
  const _$ClientError_AuthExpiredImpl() : super._();

  @override
  String toString() {
    return 'ClientError.authExpired()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_AuthExpiredImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return authExpired();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return authExpired?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (authExpired != null) {
      return authExpired();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return authExpired(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return authExpired?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (authExpired != null) {
      return authExpired(this);
    }
    return orElse();
  }
}

abstract class ClientError_AuthExpired extends ClientError {
  const factory ClientError_AuthExpired() = _$ClientError_AuthExpiredImpl;
  const ClientError_AuthExpired._() : super._();
}

/// @nodoc
abstract class _$$ClientError_InvalidResponseImplCopyWith<$Res> {
  factory _$$ClientError_InvalidResponseImplCopyWith(
          _$ClientError_InvalidResponseImpl value,
          $Res Function(_$ClientError_InvalidResponseImpl) then) =
      __$$ClientError_InvalidResponseImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$ClientError_InvalidResponseImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_InvalidResponseImpl>
    implements _$$ClientError_InvalidResponseImplCopyWith<$Res> {
  __$$ClientError_InvalidResponseImplCopyWithImpl(
      _$ClientError_InvalidResponseImpl _value,
      $Res Function(_$ClientError_InvalidResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ClientError_InvalidResponseImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ClientError_InvalidResponseImpl extends ClientError_InvalidResponse {
  const _$ClientError_InvalidResponseImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'ClientError.invalidResponse(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_InvalidResponseImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientError_InvalidResponseImplCopyWith<_$ClientError_InvalidResponseImpl>
      get copyWith => __$$ClientError_InvalidResponseImplCopyWithImpl<
          _$ClientError_InvalidResponseImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return invalidResponse(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return invalidResponse?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (invalidResponse != null) {
      return invalidResponse(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return invalidResponse(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return invalidResponse?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (invalidResponse != null) {
      return invalidResponse(this);
    }
    return orElse();
  }
}

abstract class ClientError_InvalidResponse extends ClientError {
  const factory ClientError_InvalidResponse(final String field0) =
      _$ClientError_InvalidResponseImpl;
  const ClientError_InvalidResponse._() : super._();

  String get field0;
  @JsonKey(ignore: true)
  _$$ClientError_InvalidResponseImplCopyWith<_$ClientError_InvalidResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ClientError_StorageImplCopyWith<$Res> {
  factory _$$ClientError_StorageImplCopyWith(_$ClientError_StorageImpl value,
          $Res Function(_$ClientError_StorageImpl) then) =
      __$$ClientError_StorageImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$ClientError_StorageImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_StorageImpl>
    implements _$$ClientError_StorageImplCopyWith<$Res> {
  __$$ClientError_StorageImplCopyWithImpl(_$ClientError_StorageImpl _value,
      $Res Function(_$ClientError_StorageImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ClientError_StorageImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ClientError_StorageImpl extends ClientError_Storage {
  const _$ClientError_StorageImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'ClientError.storage(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_StorageImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientError_StorageImplCopyWith<_$ClientError_StorageImpl> get copyWith =>
      __$$ClientError_StorageImplCopyWithImpl<_$ClientError_StorageImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return storage(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return storage?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (storage != null) {
      return storage(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return storage(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return storage?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (storage != null) {
      return storage(this);
    }
    return orElse();
  }
}

abstract class ClientError_Storage extends ClientError {
  const factory ClientError_Storage(final String field0) =
      _$ClientError_StorageImpl;
  const ClientError_Storage._() : super._();

  String get field0;
  @JsonKey(ignore: true)
  _$$ClientError_StorageImplCopyWith<_$ClientError_StorageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ClientError_SyncImplCopyWith<$Res> {
  factory _$$ClientError_SyncImplCopyWith(_$ClientError_SyncImpl value,
          $Res Function(_$ClientError_SyncImpl) then) =
      __$$ClientError_SyncImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$ClientError_SyncImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_SyncImpl>
    implements _$$ClientError_SyncImplCopyWith<$Res> {
  __$$ClientError_SyncImplCopyWithImpl(_$ClientError_SyncImpl _value,
      $Res Function(_$ClientError_SyncImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ClientError_SyncImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ClientError_SyncImpl extends ClientError_Sync {
  const _$ClientError_SyncImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'ClientError.sync_(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_SyncImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientError_SyncImplCopyWith<_$ClientError_SyncImpl> get copyWith =>
      __$$ClientError_SyncImplCopyWithImpl<_$ClientError_SyncImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return sync_(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return sync_?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (sync_ != null) {
      return sync_(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return sync_(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return sync_?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (sync_ != null) {
      return sync_(this);
    }
    return orElse();
  }
}

abstract class ClientError_Sync extends ClientError {
  const factory ClientError_Sync(final String field0) = _$ClientError_SyncImpl;
  const ClientError_Sync._() : super._();

  String get field0;
  @JsonKey(ignore: true)
  _$$ClientError_SyncImplCopyWith<_$ClientError_SyncImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ClientError_InvalidInputImplCopyWith<$Res> {
  factory _$$ClientError_InvalidInputImplCopyWith(
          _$ClientError_InvalidInputImpl value,
          $Res Function(_$ClientError_InvalidInputImpl) then) =
      __$$ClientError_InvalidInputImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$ClientError_InvalidInputImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_InvalidInputImpl>
    implements _$$ClientError_InvalidInputImplCopyWith<$Res> {
  __$$ClientError_InvalidInputImplCopyWithImpl(
      _$ClientError_InvalidInputImpl _value,
      $Res Function(_$ClientError_InvalidInputImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ClientError_InvalidInputImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ClientError_InvalidInputImpl extends ClientError_InvalidInput {
  const _$ClientError_InvalidInputImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'ClientError.invalidInput(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_InvalidInputImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientError_InvalidInputImplCopyWith<_$ClientError_InvalidInputImpl>
      get copyWith => __$$ClientError_InvalidInputImplCopyWithImpl<
          _$ClientError_InvalidInputImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return invalidInput(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return invalidInput?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (invalidInput != null) {
      return invalidInput(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return invalidInput(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return invalidInput?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (invalidInput != null) {
      return invalidInput(this);
    }
    return orElse();
  }
}

abstract class ClientError_InvalidInput extends ClientError {
  const factory ClientError_InvalidInput(final String field0) =
      _$ClientError_InvalidInputImpl;
  const ClientError_InvalidInput._() : super._();

  String get field0;
  @JsonKey(ignore: true)
  _$$ClientError_InvalidInputImplCopyWith<_$ClientError_InvalidInputImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ClientError_InsufficientPermissionImplCopyWith<$Res> {
  factory _$$ClientError_InsufficientPermissionImplCopyWith(
          _$ClientError_InsufficientPermissionImpl value,
          $Res Function(_$ClientError_InsufficientPermissionImpl) then) =
      __$$ClientError_InsufficientPermissionImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$ClientError_InsufficientPermissionImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res,
        _$ClientError_InsufficientPermissionImpl>
    implements _$$ClientError_InsufficientPermissionImplCopyWith<$Res> {
  __$$ClientError_InsufficientPermissionImplCopyWithImpl(
      _$ClientError_InsufficientPermissionImpl _value,
      $Res Function(_$ClientError_InsufficientPermissionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ClientError_InsufficientPermissionImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ClientError_InsufficientPermissionImpl
    extends ClientError_InsufficientPermission {
  const _$ClientError_InsufficientPermissionImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'ClientError.insufficientPermission(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_InsufficientPermissionImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientError_InsufficientPermissionImplCopyWith<
          _$ClientError_InsufficientPermissionImpl>
      get copyWith => __$$ClientError_InsufficientPermissionImplCopyWithImpl<
          _$ClientError_InsufficientPermissionImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return insufficientPermission(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return insufficientPermission?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (insufficientPermission != null) {
      return insufficientPermission(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return insufficientPermission(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return insufficientPermission?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (insufficientPermission != null) {
      return insufficientPermission(this);
    }
    return orElse();
  }
}

abstract class ClientError_InsufficientPermission extends ClientError {
  const factory ClientError_InsufficientPermission(final String field0) =
      _$ClientError_InsufficientPermissionImpl;
  const ClientError_InsufficientPermission._() : super._();

  String get field0;
  @JsonKey(ignore: true)
  _$$ClientError_InsufficientPermissionImplCopyWith<
          _$ClientError_InsufficientPermissionImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ClientError_InternalImplCopyWith<$Res> {
  factory _$$ClientError_InternalImplCopyWith(_$ClientError_InternalImpl value,
          $Res Function(_$ClientError_InternalImpl) then) =
      __$$ClientError_InternalImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$ClientError_InternalImplCopyWithImpl<$Res>
    extends _$ClientErrorCopyWithImpl<$Res, _$ClientError_InternalImpl>
    implements _$$ClientError_InternalImplCopyWith<$Res> {
  __$$ClientError_InternalImplCopyWithImpl(_$ClientError_InternalImpl _value,
      $Res Function(_$ClientError_InternalImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_$ClientError_InternalImpl(
      null == field0
          ? _value.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ClientError_InternalImpl extends ClientError_Internal {
  const _$ClientError_InternalImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'ClientError.internal(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ClientError_InternalImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ClientError_InternalImplCopyWith<_$ClientError_InternalImpl>
      get copyWith =>
          __$$ClientError_InternalImplCopyWithImpl<_$ClientError_InternalImpl>(
              this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) network,
    required TResult Function() authDeclined,
    required TResult Function() authExpired,
    required TResult Function(String field0) invalidResponse,
    required TResult Function(String field0) storage,
    required TResult Function(String field0) sync_,
    required TResult Function(String field0) invalidInput,
    required TResult Function(String field0) insufficientPermission,
    required TResult Function(String field0) internal,
  }) {
    return internal(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? network,
    TResult? Function()? authDeclined,
    TResult? Function()? authExpired,
    TResult? Function(String field0)? invalidResponse,
    TResult? Function(String field0)? storage,
    TResult? Function(String field0)? sync_,
    TResult? Function(String field0)? invalidInput,
    TResult? Function(String field0)? insufficientPermission,
    TResult? Function(String field0)? internal,
  }) {
    return internal?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? network,
    TResult Function()? authDeclined,
    TResult Function()? authExpired,
    TResult Function(String field0)? invalidResponse,
    TResult Function(String field0)? storage,
    TResult Function(String field0)? sync_,
    TResult Function(String field0)? invalidInput,
    TResult Function(String field0)? insufficientPermission,
    TResult Function(String field0)? internal,
    required TResult orElse(),
  }) {
    if (internal != null) {
      return internal(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ClientError_Network value) network,
    required TResult Function(ClientError_AuthDeclined value) authDeclined,
    required TResult Function(ClientError_AuthExpired value) authExpired,
    required TResult Function(ClientError_InvalidResponse value)
        invalidResponse,
    required TResult Function(ClientError_Storage value) storage,
    required TResult Function(ClientError_Sync value) sync_,
    required TResult Function(ClientError_InvalidInput value) invalidInput,
    required TResult Function(ClientError_InsufficientPermission value)
        insufficientPermission,
    required TResult Function(ClientError_Internal value) internal,
  }) {
    return internal(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ClientError_Network value)? network,
    TResult? Function(ClientError_AuthDeclined value)? authDeclined,
    TResult? Function(ClientError_AuthExpired value)? authExpired,
    TResult? Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult? Function(ClientError_Storage value)? storage,
    TResult? Function(ClientError_Sync value)? sync_,
    TResult? Function(ClientError_InvalidInput value)? invalidInput,
    TResult? Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult? Function(ClientError_Internal value)? internal,
  }) {
    return internal?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ClientError_Network value)? network,
    TResult Function(ClientError_AuthDeclined value)? authDeclined,
    TResult Function(ClientError_AuthExpired value)? authExpired,
    TResult Function(ClientError_InvalidResponse value)? invalidResponse,
    TResult Function(ClientError_Storage value)? storage,
    TResult Function(ClientError_Sync value)? sync_,
    TResult Function(ClientError_InvalidInput value)? invalidInput,
    TResult Function(ClientError_InsufficientPermission value)?
        insufficientPermission,
    TResult Function(ClientError_Internal value)? internal,
    required TResult orElse(),
  }) {
    if (internal != null) {
      return internal(this);
    }
    return orElse();
  }
}

abstract class ClientError_Internal extends ClientError {
  const factory ClientError_Internal(final String field0) =
      _$ClientError_InternalImpl;
  const ClientError_Internal._() : super._();

  String get field0;
  @JsonKey(ignore: true)
  _$$ClientError_InternalImplCopyWith<_$ClientError_InternalImpl>
      get copyWith => throw _privateConstructorUsedError;
}
