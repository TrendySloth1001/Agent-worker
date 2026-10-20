"use client";

import { Fragment, useState } from "react";
import { Icon } from "@/components/ui/icon";
import { Tag } from "@/components/ui/tag";
import { cn } from "@/lib/cn";
import { formatNumber } from "../lib/text";
import type { CompareData, FlowData, ProgressData, TreeData, TreeNode } from "../parsers/structure";
import { RichAction, RichFrame } from "./frame";

export function CompareCard({ data }: { data: CompareData }) {
  return (
    <RichFrame label={data.title || "Compare"}>
      <div className="grid gap-sm sm:grid-cols-[repeat(auto-fit,minmax(13rem,1fr))]">
        {data.options.map((option) => (
          <div
            key={option.name}
            className={cn(
              "flex flex-col gap-sm rounded-md bg-surface p-md",
              option.pick ? "border-[1.5px] border-text-primary" : "border border-border",
            )}
          >
            <div className="flex items-start justify-between gap-sm">
              <div className="min-w-0">
                <p className="text-body font-bold">{option.name}</p>
                {option.tagline && (
                  <p className="text-label text-text-secondary">{option.tagline}</p>
                )}
              </div>
              {option.pick && <Tag accent>Best pick</Tag>}
            </div>
            <ul className="flex flex-col gap-xs">
              {option.pros.map((pro) => (
                <li key={pro} className="flex gap-sm text-body-small">
                  <Icon name="check" size="sm" className="mt-xxs shrink-0" />
                  {pro}
                </li>
              ))}
              {option.cons.map((con) => (
                <li key={con} className="flex gap-sm text-body-small text-text-secondary">
                  <Icon name="remove" size="sm" className="mt-xxs shrink-0 text-accent-text" />
                  {con}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </RichFrame>
  );
}

const SEGMENTS = 24;

export function ProgressCard({ data }: { data: ProgressData }) {
  return (
    <RichFrame label={data.title || "Progress"}>
      <ul className="flex flex-col gap-md">
        {data.rows.map((row) => {
          const ratio = Math.min(Math.max(row.value / row.max, 0), 1);
          const lit = Math.round(ratio * (row.kind === "rating" ? row.max : SEGMENTS));
          const count = row.kind === "rating" ? row.max : SEGMENTS;
          return (
            <li key={row.label} className="flex flex-col gap-xs">
              <div className="flex items-baseline justify-between gap-md">
                <span className="text-body-small">{row.label}</span>
                <span className="font-mono text-label text-text-secondary">
                  {row.kind === "bar"
                    ? `${formatNumber(row.value)}${row.max === 100 ? "%" : ` / ${formatNumber(row.max)}`}`
                    : `${formatNumber(row.value)} / ${row.max}`}
                </span>
              </div>
              <div
                className={cn("flex", row.kind === "rating" ? "gap-xs" : "gap-px")}
                role="img"
                aria-label={`${Math.round(ratio * 100)}%`}
              >
                {Array.from({ length: count }, (_, i) => (
                  <span
                    key={i}
                    className={cn(
                      row.kind === "rating"
                        ? "size-[10px] rounded-full"
                        : "h-2.5 flex-1 rounded-[1px]",
                      i < lit ? "bg-accent" : "bg-border",
                    )}
                  />
                ))}
              </div>
              {row.kind === "bar" && row.note && (
                <p className="text-label text-text-tertiary">{row.note}</p>
              )}
            </li>
          );
        })}
      </ul>
    </RichFrame>
  );
}

function TreeRow({
  node,
  depth,
  collapsed,
  toggle,
  path,
}: {
  node: TreeNode;
  depth: number;
  collapsed: ReadonlySet<string>;
  toggle: (path: string) => void;
  path: string;
}) {
  const branch = node.children.length > 0;
  const closed = collapsed.has(path);
  return (
    <>
      <li style={{ paddingLeft: depth * 18 }}>
        <button
          type="button"
          disabled={!branch}
          onClick={() => toggle(path)}
          aria-expanded={branch ? !closed : undefined}
          className="flex min-h-8 w-full items-center gap-sm text-left"
        >
          {branch ? (
            <Icon
              name={closed ? "chevronRight" : "expand"}
              size="xs"
              className="text-text-tertiary"
            />
          ) : (
            <span className="mx-[3px] size-[5px] rounded-full bg-text-tertiary" />
          )}
          <span className={cn("font-mono text-body-small", branch && "font-bold")}>
            {node.label}
          </span>
        </button>
      </li>
      {!closed &&
        node.children.map((child, i) => (
          <TreeRow
            key={`${path}.${i}`}
            node={child}
            depth={depth + 1}
            collapsed={collapsed}
            toggle={toggle}
            path={`${path}.${i}`}
          />
        ))}
    </>
  );
}

export function TreeCard({ data }: { data: TreeData }) {
  const [collapsed, setCollapsed] = useState<ReadonlySet<string>>(new Set());
  const branches: string[] = [];
  (function walk(node: TreeNode, path: string) {
    if (node.children.length) branches.push(path);
    node.children.forEach((child, i) => walk(child, `${path}.${i}`));
  })(data.root, "0");
  const allClosed = branches.length > 0 && branches.every((path) => collapsed.has(path));

  return (
    <RichFrame
      label={data.title || "Tree"}
      flush
      actions={
        branches.length > 0 && (
          <RichAction
            icon={allClosed ? "expand" : "collapse"}
            label={allClosed ? "Expand all" : "Collapse"}
            onRun={() => setCollapsed(allClosed ? new Set() : new Set(branches))}
          />
        )
      }
    >
      <ul className="p-md">
        <TreeRow
          node={data.root}
          depth={0}
          path="0"
          collapsed={collapsed}
          toggle={(path) =>
            setCollapsed((current) => {
              const next = new Set(current);
              if (!next.delete(path)) next.add(path);
              return next;
            })
          }
        />
      </ul>
    </RichFrame>
  );
}

export function FlowCard({ data }: { data: FlowData }) {
  return (
    <RichFrame label={data.title || "Flow"}>
      <div className="flex flex-col items-stretch">
        {data.stages.map((stage, index) => (
          <Fragment key={index}>
            {index > 0 && (
              <Icon name="expand" size="sm" className="mx-auto my-xs text-text-tertiary" />
            )}
            {stage.kind === "row" ? (
              <div className="flex flex-wrap justify-center gap-sm">
                {stage.tiles.map((tile, i) => (
                  <div
                    key={i}
                    className="max-w-30 min-w-18 flex-1 rounded-md border border-border bg-surface px-sm py-sm text-center"
                  >
                    <p className="font-mono text-body font-bold">{tile.value}</p>
                    {tile.label && <p className="text-label text-text-secondary">{tile.label}</p>}
                  </div>
                ))}
              </div>
            ) : (
              <div
                className={cn(
                  "rounded-md border bg-surface px-md py-sm text-center",
                  stage.accent ? "border-[1.5px] border-accent" : "border-border",
                )}
              >
                <p className="text-body-small font-bold">{stage.title}</p>
                {stage.subtitle && (
                  <p className="text-label text-text-secondary">{stage.subtitle}</p>
                )}
              </div>
            )}
          </Fragment>
        ))}
      </div>
    </RichFrame>
  );
}
