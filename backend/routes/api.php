<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CallConfigController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\CallHistoryController;
use App\Http\Controllers\CallSessionController;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->name('api.')->middleware('throttle:demo-api')->group(function () {
    Route::post('auth/register', [AuthController::class, 'register'])->middleware('throttle:demo-register')->name('register');
    Route::post('auth/login', [AuthController::class, 'login'])->middleware('throttle:demo-login')->name('login');
    Route::post('auth/forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:3,1')->name('password.email');

    Route::middleware('auth:sanctum')->group(function () {
        Route::get('me', [AuthController::class, 'me'])->name('me');
        Route::post('auth/logout', [AuthController::class, 'logout'])->name('logout');
        Route::post('auth/email/verification-notification', [AuthController::class, 'verificationNotification'])
            ->middleware('throttle:6,1')->name('verification.send');

        Route::middleware('verified')->group(function () {
            Route::get('users', UserController::class)->name('users');
            Route::get('calls/config', CallConfigController::class)->name('calls.config');
            Route::post('calls/session', CallSessionController::class)->middleware('throttle:10,1')->name('calls.session');
            Route::get('calls/history', [CallHistoryController::class, 'index'])->name('calls.history.index');
            Route::post('calls/history', [CallHistoryController::class, 'store'])->name('calls.history.store');
            Route::patch('calls/history/{callHistory}', [CallHistoryController::class, 'update'])->name('calls.history.update');
            Route::post('broadcasting/auth', fn () => Broadcast::auth(request()))->name('broadcasting.auth');
        });
    });
});
