In a Dockerfile, both **`ENTRYPOINT`** and **`CMD`** define the command that runs when a container starts. However, they handle arguments and container flexibility differently.

Think of it this way: **`ENTRYPOINT` is the executable**, and **`CMD` is the default argument** passed to that executable.

---

## The Core Difference

* **`ENTRYPOINT`**: Defines the permanent command or executable that *will always run* when the container starts. It sets the container's primary purpose and is difficult to accidentally override.
* **`CMD`**: Defines the default command or parameters. It can be easily overridden by passing arguments at the end of the `docker run` command.

---

## How They Interact (The Best Practice)

The most powerful way to use them is **together**. You use `ENTRYPOINT` to set the application, and `CMD` to provide default flags that a user can easily change.

```dockerfile
# Example Dockerfile
FROM alpine

# Set the fixed binary to run
ENTRYPOINT ["ping"]

# Set the default argument (can be overridden)
CMD ["localhost"]

```

### Scenario A: Running without extra arguments

If you run `docker run my-ping-image`, the container executes:
`ping localhost`

### Scenario B: Overriding the argument

If you run `docker run my-ping-image google.com`, the container overrides `CMD` and executes:
`ping google.com`

---

## The Two Syntaxes: Exec vs. Shell

Both instructions can be written in two different forms, which fundamentally changes how they behave.

### 1. Exec Form (Recommended)

Written as a JSON array. It runs the executable directly without invoking a command shell.

```dockerfile
ENTRYPOINT ["/bin/echo", "Hello"]
CMD ["World"]

```

* **Why use it:** It allows Docker to pass environment variables and signals (like `SIGTERM` on stop) correctly to your application.

### 2. Shell Form

Written as a regular string. Docker implicitly prepends `/bin/sh -c` to your command.

```dockerfile
CMD echo "Hello World"

```

* **The Catch:** If you mix an Exec form `ENTRYPOINT` with a Shell form `CMD`, they won't link up correctly, and `CMD` will often be ignored or break.

---

## Summary Cheat Sheet

| Feature | `ENTRYPOINT` | `CMD` |
| --- | --- | --- |
| **Primary Purpose** | Defines the core executable of the container. | Defines default arguments or a fallback command. |
| **Overridable?** | No (unless you explicitly use the `--entrypoint` flag). | Yes, simply by adding arguments to `docker run`. |
| **When used alone** | Container acts like a dedicated binary executable. | Container runs a default command, but is highly flexible. |
| **Combined behavior** | Acts as the base command. | Acts as the default parameters appended to `ENTRYPOINT`. |

Are you trying to dockerize a specific application right now, or just mapping out the best practices for a new project?