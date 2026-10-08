<?php

namespace App\Http\Controllers;

use App\Models\CallHistory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CallHistoryController
{
    public function index(Request $request): JsonResponse
    {
        $histories = CallHistory::query()
            ->with('peer:id,name')
            ->where('user_id', $request->user()->getKey())
            ->latest('initiated_at')
            ->limit(100)
            ->get()
            ->map(fn (CallHistory $history): array => $this->serialize($history));

        return response()->json(['data' => $histories]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'peer_user_id' => ['required', 'integer', 'exists:users,id'],
            'direction' => ['required', Rule::in(['incoming', 'outgoing'])],
            'call_uuid' => ['nullable', 'uuid'],
        ]);

        abort_if((int) $validated['peer_user_id'] === (int) $request->user()->getKey(), 422, 'You cannot call yourself.');

        $history = CallHistory::query()->create([
            'user_id' => $request->user()->getKey(),
            'peer_user_id' => $validated['peer_user_id'],
            'call_uuid' => $validated['call_uuid'] ?? null,
            'direction' => $validated['direction'],
            'status' => $validated['direction'] === 'incoming' ? 'ringing' : 'initiated',
            'initiated_at' => now(),
        ])->load('peer:id,name');

        return response()->json(['data' => $this->serialize($history)], 201);
    }

    public function update(Request $request, CallHistory $callHistory): JsonResponse
    {
        abort_unless((int) $callHistory->user_id === (int) $request->user()->getKey(), 404);

        $validated = $request->validate([
            'status' => ['required', Rule::in(['ringing', 'accepted', 'connected', 'ended', 'canceled', 'rejected', 'missed', 'failed'])],
            'call_uuid' => ['nullable', 'uuid'],
        ]);

        if ($callHistory->ended_at !== null) {
            return response()->json(['data' => $this->serialize($callHistory->load('peer:id,name'))]);
        }

        $status = $validated['status'];
        $now = now();
        $updates = ['status' => $status];

        if (isset($validated['call_uuid'])) {
            $updates['call_uuid'] = $validated['call_uuid'];
        }

        if ($status === 'accepted') {
            $updates['accepted_at'] = $callHistory->accepted_at ?? $now;
        }

        if ($status === 'connected') {
            $updates['accepted_at'] = $callHistory->accepted_at ?? $now;
            $updates['connected_at'] = $callHistory->connected_at ?? $now;
        }

        if (in_array($status, ['ended', 'canceled', 'rejected', 'missed', 'failed'], true)) {
            $updates['ended_at'] = $now;
            $updates['duration_seconds'] = $callHistory->connected_at
                ? max(0, (int) $callHistory->connected_at->diffInSeconds($now))
                : 0;
        }

        $callHistory->forceFill($updates)->save();
        $callHistory->load('peer:id,name');

        return response()->json(['data' => $this->serialize($callHistory)]);
    }

    /** @return array<string, mixed> */
    private function serialize(CallHistory $history): array
    {
        return [
            'id' => $history->id,
            'peer_user_id' => $history->peer_user_id,
            'peer_name' => $history->peer?->name ?? 'Unknown user',
            'direction' => $history->direction,
            'status' => $history->status,
            'initiated_at' => $history->initiated_at?->toISOString(),
            'accepted_at' => $history->accepted_at?->toISOString(),
            'connected_at' => $history->connected_at?->toISOString(),
            'ended_at' => $history->ended_at?->toISOString(),
            'duration_seconds' => $history->duration_seconds,
        ];
    }
}
