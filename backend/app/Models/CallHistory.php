<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * @property int $id
 * @property int $user_id
 * @property int $peer_user_id
 * @property string|null $call_uuid
 * @property string $direction
 * @property string $status
 * @property Carbon $initiated_at
 * @property Carbon|null $accepted_at
 * @property Carbon|null $connected_at
 * @property Carbon|null $ended_at
 * @property int $duration_seconds
 */
class CallHistory extends Model
{
    protected $fillable = [
        'user_id',
        'peer_user_id',
        'call_uuid',
        'direction',
        'status',
        'initiated_at',
        'accepted_at',
        'connected_at',
        'ended_at',
        'duration_seconds',
    ];

    protected function casts(): array
    {
        return [
            'initiated_at' => 'datetime',
            'accepted_at' => 'datetime',
            'connected_at' => 'datetime',
            'ended_at' => 'datetime',
            'duration_seconds' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function peer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'peer_user_id');
    }
}
