import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../domain/result.dart';

AppFailure mapApiFailure(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const AppFailure(
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the server. Check your connection and try again.',
      );
    }
    var body = error.response?.data;
    if (body is List<int>) {
      try {
        body = jsonDecode(utf8.decode(body));
      } on FormatException {
        body = null;
      }
    }
    if (body is Map && body['error'] is Map) {
      final apiError = body['error'] as Map;
      return AppFailure(
        code: apiError['code'] as String? ?? 'SERVER_ERROR',
        message:
            apiError['message'] as String? ??
            'The request could not be completed.',
      );
    }
    return const AppFailure(
      code: 'SERVER_ERROR',
      message: 'The server could not complete the request. Try again.',
    );
  }
  if (error is PlatformException) {
    return const AppFailure(
      code: 'STORAGE_ERROR',
      message: 'Secure storage is unavailable. Please try again.',
    );
  }
  return const AppFailure(
    code: 'UNEXPECTED_ERROR',
    message: 'The request could not be completed. Please try again.',
  );
}
