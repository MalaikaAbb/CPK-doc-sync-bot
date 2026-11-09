// Stand-in for `next/cache` outside Next. `runDocSync` calls `refresh()` to
// re-render the page that pressed the button; there is no page here.
export function refresh(): void {}
