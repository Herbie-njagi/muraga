(() => {
  const TABLES = {
    news: { table: 'announcements', fields: { date: 'display_date' } },
    courses: { table: 'courses', fields: { dept: 'department' } },
    staff: { table: 'staff_profiles', fields: { dept: 'department', assetId: 'asset_id' } },
    gal: { table: 'gallery_items', fields: { assetId: 'asset_id' } },
    testi: { table: 'testimonials', fields: { text: 'body' } },
    apps: { table: 'applications', fields: { ref: 'reference', name: 'full_name', edu: 'education', msg: 'message', date: 'display_date', adm: 'admission_number' } },
    roster: { table: 'students', pk: 'admission_number', fields: { id: 'admission_number', name: 'full_name', total: 'total_fees', pays: 'payments', portalEnabled: 'portal_enabled', authUserId: 'auth_user_id' } },
    keys: { table: 'student_keys', pk: 'admission_number', fields: { id: 'admission_number', pub: 'public_key', wpriv: 'wrapped_private_key' } },
    stmts: { table: 'student_statements', pk: 'admission_number', fields: { id: 'admission_number', ek: 'encrypted_key', ct: 'ciphertext' } },
    payments: { table: 'student_payments', fields: { adm: 'admission_number', amt: 'amount', ref: 'reference', date: 'paid_on' } },
    results: { table: 'results', fields: { adm: 'admission_number', teacher: 'teacher_id', ek: 'encrypted_key', ct: 'ciphertext' } },
    roles: { table: 'staff_roles', pk: 'user_id', fields: { id: 'user_id' } },
    published: { table: 'trainer_result_log', fields: { adm: 'admission_number', name: 'student_name', assess: 'assessment', comp: 'competency', teacher: 'teacher_id', date: 'display_date' } }
  };

  const reverseFields = fields => Object.fromEntries(Object.entries(fields || {}).map(([from, to]) => [to, from]));
  const tableFor = name => {
    const table = TABLES[name];
    if (!table) throw new Error(`Unknown Supabase collection: ${name}`);
    return table;
  };

  function create(config) {
    if (!window.supabase?.createClient) throw new Error('Supabase client library did not load.');
    if (!config?.url || !config?.anonKey || config.url.includes('YOUR_PROJECT') || config.anonKey.includes('YOUR_SUPABASE')) {
      throw new Error('Set the Supabase project URL and anon key in assets/supabase-config.js.');
    }

    const client = window.supabase.createClient(config.url, config.anonKey);
    const listeners = new Set();
    const channels = new Set();

    function fromRow(name, row) {
      const spec = tableFor(name);
      const mapped = reverseFields(spec.fields);
      const result = {};
      for (const [key, value] of Object.entries(row)) result[mapped[key] || key] = value;
      if (name === 'keys' && result.pub && typeof result.pub !== 'string') result.pub = JSON.stringify(result.pub);
      if (name === 'roles' && result.role === 'trainer') result.role = 'teacher';
      if (name === 'results' || name === 'published') result.ts = Date.parse(row.created_at || '') || 0;
      else if (row.created_at) result.ts = Date.parse(row.created_at) || 0;
      if (name === 'published') result.id = row.id;
      return result;
    }

    function toRow(name, value, id) {
      const spec = tableFor(name);
      const result = {};
      for (const [key, item] of Object.entries(value || {})) {
        if (key === 'ts' || key === 'id' && spec.pk) continue;
        const column = spec.fields?.[key] || key;
        result[column] = item;
      }
      if (id !== undefined) result[spec.pk || 'id'] = id;
      if (name === 'keys' && typeof result.public_key === 'string') result.public_key = JSON.parse(result.public_key);
      if (name === 'roles' && result.role === 'teacher') result.role = 'trainer';
      return result;
    }

    async function queryRows(name) {
      const spec = tableFor(name);
      const { data, error } = await client.from(spec.table).select('*');
      if (error) throw error;
      const rows = (data || []).map(row => fromRow(name, row));
      if (name !== 'keys' || !rows.length) return rows;
      const { data: secretRows, error: secretError } = await client.from('student_key_secrets').select('*');
      if (secretError) throw secretError;
      const secrets = new Map((secretRows || []).map(row => [row.admission_number, row]));
      return rows.map(row => {
        const secret = secrets.get(row.id);
        return secret ? { ...row, salt: secret.salt, iv: secret.iv, wpriv: secret.wrapped_private_key } : row;
      });
    }

    async function queryAllRows(name) {
      const spec = tableFor(name);
      const pageSize = 1000;
      const rows = [];
      for (let offset = 0; ; offset += pageSize) {
        const { data, error } = await client.from(spec.table).select('*').order(spec.pk || 'id', { ascending: true }).range(offset, offset + pageSize - 1);
        if (error) throw error;
        rows.push(...(data || []).map(row => fromRow(name, row)));
        if (!data || data.length < pageSize) break;
      }
      return rows;
    }

    function snapshot(rows) {
      return { docs: rows.map(row => ({ id: row.id, data: () => row })) };
    }

    function watch(name, callback, id) {
      const spec = tableFor(name);
      let active = true;
      let queued = false;
      const reload = async () => {
        if (!active || queued) return;
        queued = true;
        try {
          const rows = await queryRows(name);
          if (active) {
            const selected = id === undefined ? rows : rows.filter(row => row.id === id);
            callback(id === undefined ? snapshot(selected) : {
              exists: () => selected.length > 0,
              data: () => selected[0]
            });
          }
        } catch (error) {
          if (active) callback(null, error);
        } finally {
          queued = false;
        }
      };
      const channel = client.channel(`watch-${spec.table}-${crypto.randomUUID()}`)
        .on('postgres_changes', { event: '*', schema: 'public', table: spec.table }, reload)
        .subscribe();
      channels.add(channel);
      listeners.add(reload);
      reload();
      return () => {
        active = false;
        listeners.delete(reload);
        channels.delete(channel);
        client.removeChannel(channel);
      };
    }

    async function write(name, operation, value, id) {
      const spec = tableFor(name);
      const table = client.from(spec.table);
      const row = toRow(name, value, id);
      if (name === 'keys' && operation === 'set') {
        const publicRow = { admission_number: row.admission_number, public_key: row.public_key };
        const secretRow = {
          admission_number: row.admission_number,
          salt: row.salt,
          iv: row.iv,
          wrapped_private_key: row.wrapped_private_key
        };
        const { error: publicError } = await client.from('student_keys').upsert(publicRow, { onConflict: 'admission_number' });
        if (publicError) throw publicError;
        const { error: secretError } = await client.from('student_key_secrets').upsert(secretRow, { onConflict: 'admission_number' });
        if (secretError) throw secretError;
        for (const reload of listeners) reload();
        return;
      }
      if (name === 'published' && !row.teacher_id) {
        const { data: { user }, error } = await client.auth.getUser();
        if (error) throw error;
        if (!user) throw new Error('Sign in before publishing results.');
        row.teacher_id = user.id;
      }
      let request;
      if (operation === 'insert') request = table.insert(row).select(spec.pk || 'id').single();
      if (operation === 'set') request = table.upsert(row, { onConflict: spec.pk || 'id' });
      if (operation === 'update') request = table.update(row).eq(spec.pk || 'id', id);
      if (operation === 'delete') request = table.delete().eq(spec.pk || 'id', id);
      const { data, error } = await request;
      if (error) throw error;
      for (const reload of listeners) reload();
      return data;
    }

    const db = {
      collection(name) {
        if (name.startsWith('data/users/') && name.endsWith('/published')) name = 'published';
        tableFor(name);
        return {
          get: async () => snapshot(await queryRows(name)),
          getAll: async () => snapshot(await queryAllRows(name)),
          add: value => write(name, 'insert', value).then(row => ({ id: row.id })),
          doc(id) {
            return {
              set: value => write(name, 'set', value, id),
              update: value => write(name, 'update', value, id),
              delete: () => write(name, 'delete', null, id),
              onSnapshot: callback => watch(name, callback, id)
            };
          },
          onSnapshot: callback => watch(name, callback)
        };
      },
      doc(path) {
        const [collection, id] = path.split('/');
        if (collection !== 'site_settings' && collection !== 'site') throw new Error(`Unknown Supabase document: ${path}`);
        const key = collection === 'site' ? id : id;
        const read = async () => {
          const { data, error } = await client.from('site_settings').select('key,value').eq('key', key).maybeSingle();
          if (error) throw error;
          return data ? { id: key, ...data.value } : null;
        };
        return {
          set: async value => {
            const { error } = await client.from('site_settings').upsert({ key, value }, { onConflict: 'key' });
            if (error) throw error;
            for (const reload of listeners) reload();
          },
          delete: async () => {
            const { error } = await client.from('site_settings').delete().eq('key', key);
            if (error) throw error;
            for (const reload of listeners) reload();
          },
          onSnapshot(callback) {
            let active = true;
            const reload = async () => {
              try {
                const row = await read();
                if (active) callback({ exists: () => !!row, data: () => row || {} });
              } catch (error) {
                if (active) callback(null, error);
              }
            };
            const channel = client.channel(`watch-setting-${key}-${crypto.randomUUID()}`)
              .on('postgres_changes', { event: '*', schema: 'public', table: 'site_settings', filter: `key=eq.${key}` }, reload)
              .subscribe();
            channels.add(channel);
            listeners.add(reload);
            reload();
            return () => {
              active = false;
              listeners.delete(reload);
              channels.delete(channel);
              client.removeChannel(channel);
            };
          }
        };
      }
    };

    const assets = {
      async upload(file) {
        const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
        const path = `${crypto.randomUUID()}-${safeName}`;
        const { error } = await client.storage.from('site-assets').upload(path, file, { cacheControl: '3600', upsert: false });
        if (error) throw error;
        return { id: path };
      },
      async delete(path) {
        if (!path) return;
        const { error } = await client.storage.from('site-assets').remove([path]);
        if (error) throw error;
      }
    };

    async function getAccess(session) {
      const user = session?.user || null;
      if (!user) return { user: null, uid: null, roles: [], isStudent: false };
      const { data: roleRows, error: roleError } = await client.from('staff_roles').select('user_id,role');
      if (roleError) throw roleError;
      const roles = (roleRows || []).map(row => fromRow('roles', row));
      if (roles.some(row => ['admin', 'admissions', 'teacher'].includes(row.role))) {
        return { user, uid: user.id, roles, isStudent: false, studentLinkMissing: false };
      }
      const { data: studentRow, error: studentError } = await client.from('students').select('admission_number').eq('auth_user_id', user.id).maybeSingle();
      const studentLinkMissing = studentError?.code === '42703';
      if (studentError && !studentLinkMissing) throw studentError;
      return {
        user,
        uid: user.id,
        roles,
        isStudent: !!studentRow,
        studentLinkMissing
      };
    }

    function dispose() {
      for (const channel of channels) client.removeChannel(channel);
      channels.clear();
      listeners.clear();
    }

    return { client, db, assets, getAccess, dispose };
  }

  function assetUrl(path) {
    if (!path || !window.MTTI_BACKEND) return '';
    return window.MTTI_BACKEND.client.storage.from('site-assets').getPublicUrl(path).data.publicUrl;
  }

  window.MTTISupabase = { create, assetUrl };
})();
