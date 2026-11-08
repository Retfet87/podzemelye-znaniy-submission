class Handler:
    

    drafts = None

    def on_message(self, ctx) -> bool:
        return False

    def on_callback(self, ctx) -> bool:
        return False
