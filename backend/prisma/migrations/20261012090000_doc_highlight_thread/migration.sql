-- Q&A thread per highlight (ASK AI on a selected passage).
ALTER TABLE "doc_highlights" ADD COLUMN "thread" JSONB NOT NULL DEFAULT '[]';
