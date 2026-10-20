export interface Greeting {
  title: string;
  subtitle: string;
}

const partOfDay = (hour: number): string => {
  if (hour >= 5 && hour < 12) return "Good morning";
  if (hour >= 12 && hour < 17) return "Good afternoon";
  if (hour >= 17 && hour < 22) return "Good evening";
  return "Up late?";
};

export function greetingOptions(name: string | undefined, hour: number): Greeting[] {
  const first = (name ?? "").trim().split(/\s+/)[0] ?? "";
  const timely = partOfDay(hour);
  return [
    {
      title: timely.endsWith("?") || !first ? timely : `${timely}, ${first}`,
      subtitle: "What are we working on?",
    },
    { title: first ? `Hey ${first}` : "Hey there", subtitle: "What's on your mind?" },
    { title: "Ask me anything", subtitle: "Code, ideas, plans, or just curious." },
    { title: "Ready when you are", subtitle: "Start a conversation." },
    { title: "Let's build", subtitle: "Bring a bug, an idea or a repo." },
    { title: "Curious today?", subtitle: "Ask, explore, or think out loud." },
    { title: "Fresh page", subtitle: "Where should we start?" },
    { title: "Hello", subtitle: "Start a conversation." },
  ];
}

export function pickGreeting(name: string | undefined, hour: number, roll: number): Greeting {
  const options = greetingOptions(name, hour);
  return options[Math.floor(roll * options.length) % options.length] as Greeting;
}
