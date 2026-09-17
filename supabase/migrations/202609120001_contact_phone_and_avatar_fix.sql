-- Match device-local phone formatting with stored international numbers.
create or replace function public.sync_phone_contacts(
  phone_numbers text[], device_names text[], device_ids text[]
)
returns table (
  uid uuid, name text, voryn_id text, display_name text,
  phone text, favorite boolean, blocked boolean
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(array_length(phone_numbers, 1), 0) > 5000 then
    raise exception 'Too many contacts in one sync';
  end if;

  insert into public.user_contacts (
    owner_uid, contact_uid, device_name, known_phone, device_contact_id, source
  )
  select auth.uid(), p.uid, nullif(trim(i.device_name), ''), i.phone_number,
         nullif(i.device_id, ''), 'matched'
  from unnest(phone_numbers, device_names, device_ids)
       as i(phone_number, device_name, device_id)
  join public.profiles p
    on (
      regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = i.phone_number
      or (
        length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) >= 10
        and length(i.phone_number) >= 10
        and right(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 10) = right(i.phone_number, 10)
      )
    )
   and p.voryn_id is not null
  where p.uid <> auth.uid()
  on conflict (owner_uid, contact_uid) do update
  set device_name = excluded.device_name,
      known_phone = excluded.known_phone,
      device_contact_id = excluded.device_contact_id,
      source = case when public.user_contacts.source = 'voryn'
                    then public.user_contacts.source else 'matched' end,
      updated_at = now();

  return query select * from public.list_my_contacts();
end;
$$;

revoke all on function public.sync_phone_contacts(text[], text[], text[]) from public;
grant execute on function public.sync_phone_contacts(text[], text[], text[]) to authenticated;
