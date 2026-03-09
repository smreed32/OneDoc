-- ============================================================================
-- Fix: Re-enable auto-profile creation trigger & create missing profile
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query)
-- ============================================================================

-- 1. Update the trigger function to handle conflicts gracefully
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.raw_user_meta_data ->> 'name', ''),
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Re-enable the trigger (it was previously disabled/missing)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 3. Create the missing profile for the Google OAuth user (Scott Reed)
--    This ensures admin role and name are set immediately.
INSERT INTO profiles (id, full_name, email, role)
VALUES ('6441555b-514e-4526-b4f3-f87a1f66374d', 'Scott Reed', 'smreed32@gmail.com', 'admin')
ON CONFLICT (id) DO UPDATE SET full_name = 'Scott Reed', role = 'admin';
