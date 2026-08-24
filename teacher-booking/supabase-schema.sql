-- قاعدة بيانات الحجوزات المشتركة
create table if not exists teachers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  required_lessons integer not null check (required_lessons >= 0),
  gold_day text,
  created_at timestamptz not null default now()
);

create table if not exists assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references teachers(id) on delete cascade,
  class_name text not null,
  subject text not null,
  required_lessons integer not null check (required_lessons > 0),
  unique(teacher_id,class_name,subject)
);

create table if not exists bookings (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references teachers(id) on delete cascade,
  day text not null,
  period integer not null check (period between 1 and 7),
  assignment_id uuid not null references assignments(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(day,period),
  unique(teacher_id,day,period)
);

create index if not exists bookings_teacher_idx on bookings(teacher_id);
create index if not exists bookings_slot_idx on bookings(day,period);

-- حجز المعلم لا يتجاوز نصابه ولا يتجاوز نصاب المقرر.
create or replace function validate_booking()
returns trigger language plpgsql as $$
declare
  teacher_required integer;
  teacher_booked integer;
  assignment_required integer;
  assignment_booked integer;
begin
  select required_lessons into teacher_required from teachers where id=new.teacher_id;
  select count(*) into teacher_booked from bookings where teacher_id=new.teacher_id;
  if tg_op='UPDATE' then teacher_booked:=teacher_booked-1; end if;
  if teacher_booked >= teacher_required then
    raise exception 'Teacher quota is complete';
  end if;

  select required_lessons into assignment_required from assignments where id=new.assignment_id;
  select count(*) into assignment_booked from bookings where teacher_id=new.teacher_id and assignment_id=new.assignment_id;
  if tg_op='UPDATE' then assignment_booked:=assignment_booked-1; end if;
  if assignment_booked >= assignment_required then
    raise exception 'Assignment quota is complete';
  end if;

  return new;
end; $$;

 drop trigger if exists trg_validate_booking on bookings;
create trigger trg_validate_booking before insert or update on bookings
for each row execute function validate_booking();

-- هذه القاعدة تمنع حجز الخانة نفسها مرتين بسبب unique(day,period).
-- قواعد قرناس يمكن إضافتها لاحقًا كـ trigger مستقل، وكذلك قيود الغرف والفصول.
