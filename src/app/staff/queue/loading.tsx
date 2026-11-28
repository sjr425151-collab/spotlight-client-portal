/**
 * AUTH-026 (OI-131): the route-level loading state of the staff work queue, shown while the
 * database derives the queue. It names no queue state, so it is never mistaken for a result.
 */
export default function QueueLoading() {
  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-10">
      <p role="status" aria-live="polite" className="text-fg-muted">
        Loading the work queue…
      </p>
    </div>
  );
}
