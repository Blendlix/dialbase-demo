<x-layouts::app :title="__('Calling Demo')">
    <div
        class="flex h-full w-full flex-1 flex-col gap-6"
        data-call-app
        data-current-user-id="{{ auth()->id() }}"
        data-session-url="{{ route('calls.session') }}"
        data-history-url="{{ route('calls.history.index') }}"
        data-csrf-token="{{ csrf_token() }}"
    >
        <div class="border-b border-neutral-200 pb-4 dark:border-neutral-700">
            <h1 class="text-xl font-semibold text-neutral-900 dark:text-white">{{ __('Dialbase Demo') }}</h1>
            <p class="mt-1 max-w-2xl text-sm leading-6 text-neutral-500 dark:text-neutral-400">{{ __('A working reference for developers adding voice calls with Dialbase. Try the demo and adapt the integration for your own app.') }}</p>
            <a href="https://dialbase.blendlix.com/docs/" target="_blank" rel="noopener noreferrer" class="mt-2 inline-flex items-center gap-2 text-sm font-medium text-neutral-700 underline underline-offset-4 dark:text-neutral-200">
                <x-flux::icon.book-open class="size-4" />
                {{ __('Dialbase docs') }}
            </a>
        </div>
        <div>
            <h2 class="text-base font-semibold text-neutral-900 dark:text-white">{{ __('Registered people') }}</h2>
            <p class="mt-1 text-sm text-neutral-500 dark:text-neutral-400">{{ $users->count() }} {{ __('registered') }}</p>
            <div class="mt-1 flex flex-wrap items-center gap-3">
                <p class="text-sm text-neutral-500 dark:text-neutral-400" data-realtime-status role="status">
                    {{ __('Connecting live presence...') }}
                </p>
                <button
                    type="button"
                    aria-pressed="true"
                    class="rounded-md border border-neutral-300 px-2.5 py-1.5 text-xs font-medium text-neutral-700 hover:bg-neutral-100 dark:border-neutral-600 dark:text-neutral-200 dark:hover:bg-neutral-800"
                    data-call-sound-toggle
                    title="{{ __('Turn off call sounds') }}"
                >
                    {{ __('Call sounds on') }}
                </button>
            </div>
        </div>

        <div class="overflow-hidden rounded-lg border border-neutral-200 dark:border-neutral-700">
            @forelse ($users as $user)
                <div class="flex items-center justify-between gap-4 border-b border-neutral-200 px-4 py-3 last:border-b-0 dark:border-neutral-700">
                    <span class="min-w-0 truncate font-medium text-neutral-900 dark:text-white">{{ $user->name }}</span>
                    <div class="flex shrink-0 items-center gap-3">
                        <span class="text-xs text-neutral-500 dark:text-neutral-400" data-user-live-status="{{ $user->id }}">{{ __('Offline') }}</span>
                        <button
                            type="button"
                            aria-label="{{ __('Call :name', ['name' => $user->name]) }}"
                            class="inline-flex items-center gap-2 rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-neutral-600 dark:text-neutral-200 dark:hover:bg-neutral-800"
                            data-call-user-id="{{ $user->id }}"
                            data-call-user-name="{{ $user->name }}"
                            disabled
                        >
                            <x-flux::icon.phone class="size-4" />
                            {{ __('Call') }}
                        </button>
                    </div>
                </div>
            @empty
                <p class="px-4 py-6 text-sm text-neutral-500 dark:text-neutral-400">{{ __('No registered people yet.') }}</p>
            @endforelse
        </div>

        <p class="text-sm text-neutral-500 dark:text-neutral-400" data-call-status role="status" aria-live="polite">
            {{ __('Connecting to call service...') }}
        </p>

        <dialog class="call-window" data-call-panel aria-labelledby="call-window-title" aria-describedby="call-window-status" hidden>
            <header class="call-window-header">
                <span class="call-phase"><x-flux::icon.phone class="size-4" /><span data-call-phase>{{ __('Audio call') }}</span></span>
                <button type="button" class="call-minimize" data-call-minimize title="{{ __('Minimize call') }}" aria-label="{{ __('Minimize call') }}" hidden>
                    <x-flux::icon.minus class="size-5" />
                </button>
            </header>
            <div class="call-window-body">
                <div class="call-avatar" data-call-avatar aria-hidden="true"></div>
                <h2 id="call-window-title" data-call-peer></h2>
                <p id="call-window-status" class="call-dialog-status" data-call-dialog-status role="status" aria-live="polite"></p>
                <p class="call-duration" data-call-duration role="timer" aria-live="off" hidden>00:00</p>
                <button type="button" class="call-play-audio" data-call-play-audio hidden><x-flux::icon.speaker-wave class="size-4" />{{ __('Play audio') }}</button>
            </div>
            <footer class="call-controls">
                <button type="button" class="call-control call-control-decline" data-call-reject title="{{ __('Decline call') }}" hidden>
                    <span class="call-control-icon"><x-flux::icon.phone-x-mark class="size-6" /></span><span>{{ __('Decline') }}</span>
                </button>
                <button type="button" class="call-control call-control-answer" data-call-accept title="{{ __('Answer call') }}" hidden>
                    <span class="call-control-icon"><x-flux::icon.phone class="size-6" /></span><span>{{ __('Answer') }}</span>
                </button>
                <button type="button" class="call-control call-control-mute" data-call-mute title="{{ __('Mute microphone') }}" aria-pressed="false" hidden>
                    <span class="call-control-icon"><span data-call-mic-on><x-flux::icon.microphone class="size-6" /></span><span class="call-mic-off" data-call-mic-off hidden><x-flux::icon.microphone class="size-6" /></span></span><span data-call-mute-label>{{ __('Mute') }}</span>
                </button>
                <button type="button" class="call-control call-control-decline" data-call-end title="{{ __('Cancel call') }}" hidden>
                    <span class="call-control-icon"><x-flux::icon.phone-x-mark class="size-6" /></span><span data-call-end-label>{{ __('Cancel') }}</span>
                </button>
            </footer>
        </dialog>
        <button type="button" class="call-dock" data-call-restore title="{{ __('Open call window') }}" aria-label="{{ __('Open call window') }}" hidden>
            <span class="call-dock-icon"><x-flux::icon.phone class="size-5" /></span>
            <span class="call-dock-identity"><span data-call-mini-name></span><span data-call-mini-duration>00:00</span></span>
            <x-flux::icon.chevron-up class="size-4" />
        </button>
        <audio class="hidden" data-call-audio autoplay playsinline></audio>

        <section class="space-y-3 border-t border-neutral-200 pt-5" aria-labelledby="call-history-heading">
            <div class="flex items-baseline justify-between gap-4">
                <h2 id="call-history-heading" class="text-base font-semibold text-neutral-900 dark:text-white">{{ __('Call history') }}</h2>
                <span class="text-xs text-neutral-500 dark:text-neutral-400">{{ __('Latest 100') }}</span>
            </div>

            <div class="overflow-hidden rounded-lg border border-neutral-200 dark:border-neutral-700" data-call-history-list>
                @forelse ($callHistories as $history)
                    <article class="flex flex-wrap items-center justify-between gap-x-6 gap-y-2 border-b border-neutral-200 px-4 py-3 last:border-b-0 dark:border-neutral-700" data-history-id="{{ $history->id }}">
                        <div class="min-w-0">
                            <p class="truncate font-medium text-neutral-900 dark:text-white" data-history-peer>{{ $history->peer->name }}</p>
                            <p class="mt-0.5 text-xs text-neutral-500 dark:text-neutral-400" data-history-meta>
                                {{ ucfirst($history->direction) }} · {{ $history->initiated_at->format('M j, Y H:i') }}
                            </p>
                        </div>
                        <div class="flex shrink-0 items-center gap-4 text-sm">
                            <span class="text-neutral-600 dark:text-neutral-300" data-history-status>{{ ucfirst($history->status) }}</span>
                            <time class="font-mono tabular-nums text-neutral-700 dark:text-neutral-200" data-history-duration>{{ gmdate($history->duration_seconds >= 3600 ? 'H:i:s' : 'i:s', $history->duration_seconds) }}</time>
                        </div>
                    </article>
                @empty
                    <p class="px-4 py-6 text-sm text-neutral-500 dark:text-neutral-400" data-history-empty>{{ __('No calls yet.') }}</p>
                @endforelse
            </div>
        </section>
    </div>
</x-layouts::app>
