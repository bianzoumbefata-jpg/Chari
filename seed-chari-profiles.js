const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = "https://xitiqkemodqxbitgwihi.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_9hQoNBq5YB-G0u9swyLm-w_lgc_RQfP";

const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const REAL_PROFILES = [
  // FEMMES TCHADIENNES
  {
    name: "Achta",
    gender: "f",
    age: 24,
    city: "N'Djamena",
    target_city: "all",
    job: "Infirmière en pédiatrie",
    bio: "Passionnée par la santé des enfants et la cuisine tchadienne. J'aime les discussions sincères, le respect mutuel et je recherche une relation durable.",
    language: "fr",
    religion: "mus",
    children: 0,
    intention: "mar",
    hobbies: ["cui", "lec", "voy"],
    selfie_url: "photos/achte.jpg",
    is_verified: true,
    is_premium: false
  },
  {
    name: "Fatimé",
    gender: "f",
    age: 26,
    city: "Abéché",
    target_city: "all",
    job: "Comptable d'entreprise",
    bio: "Calme, organisée et curieuse. J'aime la lecture, le thé à la menthe et les moments en famille. Prête pour un bel engagement.",
    language: "both",
    religion: "mus",
    children: 0,
    intention: "mar",
    hobbies: ["lec", "cui", "ent"],
    selfie_url: "photos/fatime.jpg",
    is_verified: true,
    is_premium: true
  },
  {
    name: "Hawa",
    gender: "f",
    age: 23,
    city: "Moundou",
    target_city: "all",
    job: "Diplômée en Droit & entrepreneure",
    bio: "Souriante, ambitieuse et spontanée. J'aime le sport, les voyages et le football. À la recherche de quelqu'un de sérieux et respectueux.",
    language: "fr",
    religion: "chr",
    children: 0,
    intention: "ser",
    hobbies: ["spo", "foo", "voy"],
    selfie_url: "photos/hawa.jpg",
    is_verified: true,
    is_premium: false
  },
  {
    name: "Mariam",
    gender: "f",
    age: 27,
    city: "Sarh",
    target_city: "all",
    job: "Institutrice de lycée",
    bio: "Passionnée d'éducation, de musique et de poésie. J'apprécie la simplicité, la loyauté et les fous rires partagés.",
    language: "both",
    religion: "mus",
    children: 0,
    intention: "mar",
    hobbies: ["mus", "lec", "cui"],
    selfie_url: "photos/mariam.jpg",
    is_verified: true,
    is_premium: false
  },
  // HOMMES TCHADIENS
  {
    name: "Mahamat",
    gender: "m",
    age: 28,
    city: "N'Djamena",
    target_city: "all",
    job: "Ingénieur en télécommunications",
    bio: "Posé, dynamique et travailleur. Passionné de nouvelles technologies et de sport. Je cherche une complice bienveillante pour construire un foyer.",
    language: "both",
    religion: "mus",
    children: 0,
    intention: "mar",
    hobbies: ["spo", "foo", "ent"],
    selfie_url: "photos/mahamat.jpg",
    is_verified: true,
    is_premium: true
  },
  {
    name: "Abakar",
    gender: "m",
    age: 30,
    city: "Abéché",
    target_city: "all",
    job: "Ingénieur agronome & entrepreneur",
    bio: "Le football le week-end, la famille toute l'année. Homme de parole, calme et à l'écoute. En quête d'une relation solide et sincère.",
    language: "both",
    religion: "mus",
    children: 0,
    intention: "mar",
    hobbies: ["foo", "ent", "voy"],
    selfie_url: "photos/abakar.jpg",
    is_verified: true,
    is_premium: false
  },
  {
    name: "Idriss",
    gender: "m",
    age: 26,
    city: "Moundou",
    target_city: "all",
    job: "Développeur web & graphiste",
    bio: "Créatif, curieux et toujours de bonne humeur. J'aime les cafés, les projets numériques et les sorties entre amis.",
    language: "fr",
    religion: "chr",
    children: 0,
    intention: "ser",
    hobbies: ["jv", "cin", "mus"],
    selfie_url: "photos/idriss.jpg",
    is_verified: true,
    is_premium: false
  },
  {
    name: "Moussa",
    gender: "m",
    age: 29,
    city: "Sarh",
    target_city: "all",
    job: "Médecin généraliste",
    bio: "Sérieux dans mon travail mais avec beaucoup d'humour dans la vie. J'aime les longues discussions, la lecture et la nature.",
    language: "both",
    religion: "mus",
    children: 0,
    intention: "mar",
    hobbies: ["lec", "voy", "spo"],
    selfie_url: "photos/moussa.jpg",
    is_verified: true,
    is_premium: false
  }
];

async function seed() {
  console.log("Insertion des profils réels dans Supabase...");
  for (const prof of REAL_PROFILES) {
    const { data: existing } = await sb
      .from('profiles')
      .select('id')
      .eq('name', prof.name)
      .eq('gender', prof.gender)
      .eq('city', prof.city)
      .limit(1);

    if (existing && existing.length > 0) {
      const { data, error } = await sb
        .from('profiles')
        .update(prof)
        .eq('id', existing[0].id)
        .select();
      if (error) {
        console.error(`Erreur mise à jour ${prof.name}:`, error.message);
      } else {
        console.log(`Mis à jour: ${prof.name} -> ID: ${data[0].id}`);
      }
    } else {
      const { data, error } = await sb
        .from('profiles')
        .insert(prof)
        .select();
      if (error) {
        console.error(`Erreur insertion ${prof.name}:`, error.message);
      } else {
        console.log(`Inséré: ${prof.name} -> ID: ${data[0].id}`);
      }
    }
  }
  console.log("Terminé avec succès !");
}

seed().catch(console.error);
