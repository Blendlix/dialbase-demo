<?php

use App\Http\Controllers\CallHistoryController;
use App\Http\Controllers\CallSessionController;
use App\Models\CallHistory;
use App\Models\User;
use Illuminate\Support\Facades\Route;

Route::view('/', 'welcome')->name('home');

Route::middleware(['auth', 'verified'])->group(function () {
    Route::post('calls/session', CallSessionController::class)->name('calls.session');
    Route::get('calls/history', [CallHistoryController::class, 'index'])->name('calls.history.index');
    Route::post('calls/history', [CallHistoryController::class, 'store'])->name('calls.history.store');
    Route::patch('calls/history/{callHistory}', [CallHistoryController::class, 'update'])->name('calls.history.update');

    Route::get('dashboard', function () {
        return view('dashboard', [
            'users' => User::query()
                ->where('id', '!=', auth()->id())
                ->orderBy('name')
                ->get(),
            'callHistories' => CallHistory::query()
                ->with('peer:id,name')
                ->where('user_id', auth()->id())
                ->latest('initiated_at')
                ->limit(100)
                ->get(),
        ]);
    })->name('dashboard');
});

require __DIR__.'/settings.php';
