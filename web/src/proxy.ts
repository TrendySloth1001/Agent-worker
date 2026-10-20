import { NextResponse, type NextRequest } from "next/server";
import { guardRoute } from "@/lib/route-guard";
import { ACCESS_COOKIE } from "@/server/cookie-names";
import { PATH_HEADER } from "@/server/headers";

export function proxy(req: NextRequest) {
  const { pathname, search } = req.nextUrl;
  const decision = guardRoute(pathname, search, req.cookies.has(ACCESS_COOKIE));
  if (decision.action === "redirect") {
    const target = req.nextUrl.clone();
    const [path = "/", query] = decision.location.split("?");
    target.pathname = path;
    target.search = query ? `?${query}` : "";
    return NextResponse.redirect(target);
  }
  const headers = new Headers(req.headers);
  headers.set(PATH_HEADER, `${pathname}${search}`);
  return NextResponse.next({ request: { headers } });
}

export const config = {
  matcher: ["/((?!api/|_next/|.*\\..*).*)"],
};
