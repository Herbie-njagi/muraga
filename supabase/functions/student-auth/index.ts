import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json' }
});

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) return json({ error: 'Student authentication is not configured.' }, 500);

  try {
    const body = await request.json();
    const identifier = String(body.identifier || body.admissionNumber || '').trim();
    const admissionNumber = String(body.admissionNumber || identifier).trim().toUpperCase().replace(/[\s/\\]+/g, '-');
    const password = String(body.password || '');
    const action = body.action;
    if (!identifier || password.length < 8 || password.length > 128 || !['login', 'signup'].includes(action)) {
      return json({ error: 'Enter an admission number or full name and a password of at least 8 characters.' }, 400);
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    });
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    });

    const { data: admittedStudent, error: studentError } = await adminClient
      .from('students')
      .select('email, auth_user_id, portal_enabled')
      .eq('admission_number', admissionNumber)
      .maybeSingle();
    if (studentError) {
      console.error('Student lookup failed:', studentError.message);
      if (studentError.code === '42703' || studentError.code === 'PGRST204') {
        return json({ error: 'Student accounts are not ready. Ask the administrator to run the latest Supabase migrations.' }, 503);
      }
      return json({ error: 'Student sign-in is temporarily unavailable.' }, 500);
    }

    let student = admittedStudent;
    if (!student && action === 'login') {
      const exactName = identifier.replace(/\s+/g, ' ').replace(/[\\%_*]/g, '\\$&');
      const { data: nameMatches, error: nameError } = await adminClient
        .from('students')
        .select('email, auth_user_id, portal_enabled')
        .ilike('full_name', exactName)
        .limit(2);
      if (nameError) {
        console.error('Student name lookup failed:', nameError.message);
        return json({ error: 'Student sign-in is temporarily unavailable.' }, 500);
      }
      if (nameMatches?.length === 1) student = nameMatches[0];
    }

    const email = String(body.email || '').trim().toLowerCase();
    if (!student?.portal_enabled || !student.email || (action === 'signup' && student.email.trim().toLowerCase() !== email)) {
      return json({ error: 'Admission number, full name, email, or password is incorrect.' }, 401);
    }
    if (action === 'signup' && student.auth_user_id) {
      return json({ error: 'This student account is already registered. Use Sign In or contact admissions.' }, 409);
    }

    const authResult = action === 'signup'
      ? await authClient.auth.signUp({
          email: student.email,
          password,
          options: { data: { admission_number: admissionNumber } }
        })
      : await authClient.auth.signInWithPassword({ email: student.email, password });

    if (authResult.error) {
      console.error(`Student ${action} failed:`, authResult.error.message);
      return json({ error: action === 'login'
        ? 'Admission number or full name and password are incorrect.'
        : 'Unable to create the account. Check the email and password, or contact admissions.' }, 401);
    }

    const user = authResult.data.user;
    if (action === 'login' && student.auth_user_id && user?.id !== student.auth_user_id) {
      return json({ error: 'Admission number or full name and password are incorrect.' }, 401);
    }

    const session = authResult.data.session;
    return json({
      needsEmailConfirmation: action === 'signup' && !session,
      session: session ? {
        access_token: session.access_token,
        refresh_token: session.refresh_token
      } : null
    });
  } catch (error) {
    console.error('Student authentication request failed:', error);
    return json({ error: 'Unable to complete student authentication.' }, 400);
  }
});
