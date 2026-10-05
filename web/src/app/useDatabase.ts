import { useEffect, useState } from 'react';
import { openDatabase, type OpenedDatabase } from './database';

/** DB を一度だけ開いて共有する薄いフック。開くまで db=null。 */
export function useDatabase(): { db: OpenedDatabase | null; error: string | null } {
  const [db, setDb] = useState<OpenedDatabase | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    openDatabase()
      .then((opened) => {
        if (alive) setDb(opened);
      })
      .catch((e: unknown) => {
        console.error('DB open failed', e);
        if (alive) setError(e instanceof Error ? e.message : String(e));
      });
    return () => {
      alive = false;
    };
  }, []);

  return { db, error };
}
