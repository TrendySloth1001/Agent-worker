import { Divider } from "@/components/ui/divider";
import { DotLoader } from "@/components/ui/dot-loader";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { Section } from "./section";

export function FeedbackSection() {
  return (
    <>
      <Section title="Loading">
        <div className="flex items-center gap-xl">
          <Spinner />
          <DotLoader />
        </div>
        <div className="flex max-w-[28rem] flex-col gap-sm">
          <Skeleton className="h-3 w-full" />
          <Skeleton className="h-3 w-4/5" />
          <Skeleton className="h-3 w-2/5" />
        </div>
      </Section>
      <Section title="Divider">
        <div className="flex h-8 max-w-[28rem] items-center gap-md">
          <span className="text-body-small">One</span>
          <Divider vertical />
          <span className="text-body-small">Two</span>
        </div>
        <Divider className="max-w-[28rem]" />
      </Section>
    </>
  );
}
